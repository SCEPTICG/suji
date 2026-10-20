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
    function mp.set_property_bool(name, v) mp.props[name] = v; mp.fire(name, v) end
    function mp.commandv(...) mp.commands[#mp.commands + 1] = { ... } end

    function mp.observe_property(name, _, fn)
        mp.observers[name] = mp.observers[name] or {}
        table.insert(mp.observers[name], fn)
    end
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
            mp.updates[#mp.updates + 1] = { data = self.data, w = self.res_x, h = self.res_y }
        end
        function ov.remove() end
        return ov
    end

    local function log(level) return function(...) table.insert(mp.logs, { level, ... }) end end
    package.loaded["mp.msg"] = { info = log("info"), warn = log("warn"), error = log("error"),
                                 debug = log("debug") }
    package.loaded["mp.options"] = { read_options = function(t, _, _)
        for k, v in pairs(mp.script_opts or {}) do t[k] = v end
    end }
    return mp
end

-- Forget suji's modules so each scenario starts from a clean state.
function T.unload()
    for _, name in ipairs({ "options", "state", "draw", "animation", "painter", "mouse",
                            "visibility", "elements.bar", "main" }) do
        package.loaded[name] = nil
    end
end

return T
