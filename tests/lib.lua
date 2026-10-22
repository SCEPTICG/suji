-- Tiny test helpers and a fake `mp` for running suji outside mpv.
-- Run from the repository root through tests/run.sh, which sets LUA_PATH.

local T = { failures = 0, count = 0 }

function T.check(cond, name)
    T.count = T.count + 1
    if not cond then
        T.failures = T.failures + 1
        io.stderr:write("FAIL: " .. name .. "\n")
    end
end

function T.eq(got, want, name)
    T.check(got == want, ("%s (got %s, want %s)"):format(name, tostring(got), tostring(want)))
end

function T.near(got, want, name, eps)
    T.check(type(got) == "number" and math.abs(got - want) <= (eps or 1e-6),
        ("%s (got %s, want %s)"):format(name, tostring(got), tostring(want)))
end

function T.done(file)
    print(("%s: %d checks, %d failed"):format(file, T.count, T.failures))
    os.exit(T.failures == 0 and 0 or 1)
end

-- What mpv's parse_json puts on the tables it makes (mp.MAP, mp.ARRAY).
T.MAP, T.ARRAY = { type = "MAP" }, { type = "ARRAY" }

-- Fake mp: a manual clock, one-shot timers, observers, key bindings, a
-- command log and an overlay that records every update().
function T.fake_mp(props)
    local mp = { MAP = T.MAP, ARRAY = T.ARRAY, now = 100, timers = {}, observers = {}, bindings = {},
                 commands = {}, updates = {}, props = props or {}, logs = {} }

    function mp.get_time() return mp.now end
    function mp.get_property(name, def) return mp.props[name] or def end
    function mp.get_property_number(name, def) return tonumber(mp.props[name]) or def end
    function mp.get_property_native(name, def) return mp.props[name] or def end
    function mp.get_property_bool(name, def)
        local v = mp.props[name]
        if v == nil then return def end
        return v
    end
    function mp.set_property_bool(name, v) mp.props[name] = v; mp.fire(name, v) end
    -- Writes of set_property_native and del_property, in order: { name, value }.
    mp.writes = {}
    function mp.set_property_native(name, v)
        mp.writes[#mp.writes + 1] = { name, v }
        mp.props[name] = v
        mp.fire(name, v)
    end
    function mp.del_property(name)
        mp.writes[#mp.writes + 1] = { name }
        mp.props[name] = nil
        mp.fire(name, nil)
    end
    if mp.props["input-builtin-dragging"] == nil then mp.props["input-builtin-dragging"] = true end

    mp.events = {}
    function mp.register_event(name, fn)
        mp.events[name] = mp.events[name] or {}
        table.insert(mp.events[name], fn)
    end
    function mp.emit(name)
        for _, fn in ipairs(mp.events[name] or {}) do fn({ event = name }) end
    end

    -- Mouse with mpv's built-in window dragging: moving more than 3 px with
    -- the button held cancels the button (event up, canceled) unless
    -- input-builtin-dragging is off.
    local held
    function mp.mouse(x, y, hover)
        if hover == nil then hover = true end
        mp.props["mouse-pos"] = { x = x, y = y, hover = hover }
        mp.fire("mouse-pos", mp.props["mouse-pos"])
        if held and mp.props["input-builtin-dragging"] ~= false and
            (math.abs(x - held.x) > 3 or math.abs(y - held.y) > 3) then
            held = nil
            local b = mp.bindings["suji-bar"]
            if b then b.fn({ event = "up", canceled = true }) end
        end
        mp.last_mouse = { x = x, y = y }
    end
    function mp.button(event, canceled)
        if event == "down" then held = mp.last_mouse else held = nil end
        local b = mp.bindings["suji-bar"]
        if b then b.fn({ event = event, canceled = canceled }) end
    end
    function mp.commandv(...) mp.commands[#mp.commands + 1] = { ... } end
    function mp.command(s) mp.commands[#mp.commands + 1] = { s } end
    -- expand-path of ~~state/ gives mp.state_dir, else "" (mpv with
    -- --no-config): no test touches the disk unless it sets one.
    function mp.command_native(c)
        if c[1] == "expand-path" and c[2] == "~~state/" then return mp.state_dir or "" end
    end
    mp.messages = {}
    function mp.register_script_message(name, fn) mp.messages[name] = fn end
    -- script-message-to suji name ...
    function mp.send(name, ...) mp.messages[name](...) end

    mp.observed = {} -- number of observe_property calls per property
    -- With mp.async_observe set, every new observer gets the property's
    -- value (nil for kind "none") once, at the next advance, as mpv does.
    -- Off by default: the older tests fire every value by hand.
    local initial = {}
    function mp.observe_property(name, kind, fn)
        mp.observers[name] = mp.observers[name] or {}
        table.insert(mp.observers[name], fn)
        mp.observed[name] = (mp.observed[name] or 0) + 1
        if mp.async_observe then initial[#initial + 1] = { name = name, kind = kind, fn = fn } end
    end
    function mp.unobserve_property(fn)
        for _, list in pairs(mp.observers) do
            for i = #list, 1, -1 do if list[i] == fn then table.remove(list, i) end end
        end
        for _, it in ipairs(initial) do if it.fn == fn then it.gone = true end end
    end
    local function deliver_initial()
        local list = initial
        initial = {}
        for _, it in ipairs(list) do
            if not it.gone then it.fn(it.name, it.kind ~= "none" and mp.props[it.name] or nil) end
        end
    end
    -- Observers still registered for a property.
    function mp.live(name) return #(mp.observers[name] or {}) end
    function mp.fire(name, value)
        for _, fn in ipairs(mp.observers[name] or {}) do fn(name, value) end
    end

    function mp.add_forced_key_binding(key, name, fn, flags)
        mp.bindings[name] = { key = key, fn = fn, flags = flags }
    end
    function mp.remove_key_binding(name) mp.bindings[name] = nil end

    function mp.add_timeout(seconds, fn, disabled)
        local t = { timeout = seconds, fn = fn, enabled = false, due = 0 }
        function t.is_enabled(self) return self.enabled end
        function t.kill(self) self.enabled = false end
        function t.stop(self) self.enabled = false end
        function t.resume(self) self.enabled = true; self.due = mp.now + self.timeout end
        mp.timers[#mp.timers + 1] = t
        if not disabled then t:resume() end
        return t
    end
    function mp.active_timers()
        local n = 0
        for _, t in ipairs(mp.timers) do if t.enabled then n = n + 1 end end
        return n
    end
    -- Advance the clock, firing due timers in order.
    function mp.advance(dt)
        deliver_initial()
        local stop = mp.now + dt
        while true do
            local next_t
            for _, t in ipairs(mp.timers) do
                if t.enabled and t.due <= stop and (not next_t or t.due < next_t.due) then
                    next_t = t
                end
            end
            if not next_t then break end
            mp.now = math.max(mp.now, next_t.due)
            next_t.enabled = false
            next_t.fn()
        end
        mp.now = stop
    end

    function mp.create_osd_overlay(format)
        local ov = { format = format, data = "", res_x = 0, res_y = 720 }
        function ov.update(self)
            if self.hidden then -- measuring
                mp.probes = (mp.probes or 0) + 1
                return mp.probe_result
            end
            mp.updates[#mp.updates + 1] = { data = self.data, w = self.res_x, h = self.res_y }
        end
        function ov.remove() end
        return ov
    end

    local function log(level) return function(...) table.insert(mp.logs, { level, ... }) end end
    package.loaded["mp.msg"] = { info = log("info"), warn = log("warn"), error = log("error"),
                                 debug = log("debug") }
    -- Options: mp.script_opts at start; mp.set_opts(t) changes them at run
    -- time like the script-opts property, calling on_update with the list.
    -- mp.parse_json, when set, replaces what the JSON would give.
    package.loaded["mp.utils"] = { parse_json = function(s)
        if mp.parse_json then return mp.parse_json(s) end
        return T.parse_json(s)
    end }
    package.loaded["mp.options"] = { read_options = function(t, _, on_update)
        for k, v in pairs(mp.script_opts or {}) do t[k] = v end
        function mp.set_opts(new)
            local changed = {}
            for k, v in pairs(new) do
                if t[k] ~= v then t[k], changed[k] = v, true end
            end
            if on_update and next(changed) then on_update(changed) end
        end
    end }
    return mp
end

-- JSON for the tests: T.json writes a Lua value (a table with [1] or with
-- nothing is a list), T.parse_json reads it like mpv's utils.parse_json:
-- nil and an error for anything broken, objects with the metatable T.MAP
-- and lists with T.ARRAY. \u escapes only go up to 127.
function T.json(v)
    local t = type(v)
    if t == "string" then
        return '"' .. v:gsub('[%c"\\]', function(c) return ("\\u%04x"):format(c:byte()) end) .. '"'
    elseif t == "table" then
        local out = {}
        if next(v) == nil or v[1] ~= nil then
            for i = 1, #v do out[i] = T.json(v[i]) end
            return "[" .. table.concat(out, ",") .. "]"
        end
        for k, x in pairs(v) do out[#out + 1] = T.json(tostring(k)) .. ":" .. T.json(x) end
        table.sort(out)
        return "{" .. table.concat(out, ",") .. "}"
    elseif v == nil then
        return "null"
    end
    return tostring(v)
end

local ESCAPES = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
function T.parse_json(s)
    local i = 1
    local function ws() i = s:find("[^ \t\r\n]", i) or #s + 1 end
    local function str()
        local out = {}
        i = i + 1
        while true do
            local j = s:find('["\\]', i) or error("unterminated string")
            out[#out + 1] = s:sub(i, j - 1)
            i = j
            if s:sub(i, i) == '"' then i = i + 1; return table.concat(out) end
            local e = s:sub(i + 1, i + 1)
            if e == "u" then
                local n = tonumber(s:sub(i + 2, i + 5), 16) or error("bad escape")
                out[#out + 1] = n < 128 and string.char(n) or "?"
                i = i + 6
            else
                out[#out + 1] = ESCAPES[e] or error("bad escape")
                i = i + 2
            end
        end
    end
    local value
    local function list(close, item)
        i = i + 1
        ws()
        if s:sub(i, i) == close then i = i + 1; return end
        while true do
            item()
            ws()
            local c = s:sub(i, i)
            i = i + 1
            if c == close then return end
            if c ~= "," then error("expected , or " .. close) end
        end
    end
    function value()
        ws()
        local c = s:sub(i, i)
        if c == "{" then
            local t = setmetatable({}, T.MAP)
            list("}", function()
                ws()
                if s:sub(i, i) ~= '"' then error("expected a key") end
                local k = str()
                ws()
                if s:sub(i, i) ~= ":" then error("expected :") end
                i = i + 1
                t[k] = value()
            end)
            return t
        elseif c == "[" then
            local t, n = setmetatable({}, T.ARRAY), 0
            list("]", function() n = n + 1; t[n] = value() end)
            return t
        elseif c == '"' then
            return str()
        end
        for word, v in pairs({ ["true"] = true, ["false"] = false, null = "null" }) do
            if s:sub(i, i + #word - 1) == word then
                i = i + #word
                if v == "null" then return nil end
                return v
            end
        end
        local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
        if not num or not tonumber(num) then error("unexpected '" .. c .. "'") end
        i = i + #num
        return tonumber(num)
    end
    local ok, v = pcall(function()
        local v = value()
        ws()
        if i <= #s then error("trailing data") end
        return v
    end)
    if not ok then return nil, "error" end
    return v
end

-- Forget suji's files so each scenario starts from a clean state.
function T.unload()
    for name in pairs(package.loaded) do
        if name == "main" or name:find("^core%.") or name:find("^modules%.") then package.loaded[name] = nil end
    end
end

return T
