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

-- Fake mp: a manual clock, one-shot timers, observers, key bindings, a
-- command log and an overlay that records every update().
function T.fake_mp(props)
    local mp = { now = 100, timers = {}, observers = {}, bindings = {},
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
    mp.messages = {}
    function mp.register_script_message(name, fn) mp.messages[name] = fn end

    mp.observed = {} -- number of observe_property calls per property
    function mp.observe_property(name, _, fn)
        mp.observers[name] = mp.observers[name] or {}
        table.insert(mp.observers[name], fn)
        mp.observed[name] = (mp.observed[name] or 0) + 1
    end
    function mp.unobserve_property(fn)
        for _, list in pairs(mp.observers) do
            for i = #list, 1, -1 do if list[i] == fn then table.remove(list, i) end end
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

-- Forget suji's files so each scenario starts from a clean state.
function T.unload()
    for name in pairs(package.loaded) do
        if name == "main" or name:find("^core%.") or name:find("^modules%.") then package.loaded[name] = nil end
    end
end

return T
