-- Speed: the usual playback speeds, the current one marked. Away from 1x
-- the button shows the speed, small, in its top right corner (the row
-- does not move). Shown whenever mpv is not idle with no file.

local base = require "modules.menu_button"

local SPEEDS = { 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 3, 4 }
local TIMES = "\195\151" -- ×

local idle = false -- idle-active: no file
local label        -- the speed in the corner, nil at 1x

-- 1.5, 0.75, 2, 1.23: at most 4 characters, no zeros at the end.
local function short(speed)
    local s
    for d = 2, 0, -1 do
        s = ("%." .. d .. "f"):format(speed)
        if d > 0 then s = s:gsub("0+$", ""):gsub("%.$", "") end
        if #s <= 4 then break end
    end
    return s .. TIMES
end

local function on(speed, s) return math.abs(speed - s) < 0.001 end

local b = base.new({
    icon = "speed",
    live = { "speed" },

    init = function(ctx)
        ctx.watch("idle-active", "native", function(v)
            if (v == true) ~= idle then
                idle = v == true
                ctx.relayout()
            end
        end)
        ctx.watch("speed", "number", function(v)
            local l = v and not on(v, 1) and short(v) or nil
            if l == label then return end
            label = l
            return true -- a paint, if the controls are on screen
        end)
    end,

    available = function() return not idle end,

    build = function()
        local speed = mp.get_property_number("speed") or 1
        local items, any = {}, false
        for i, s in ipairs(SPEEDS) do
            items[i] = { title = ("%g"):format(s) .. TIMES, active = on(speed, s), value = { "set", "speed", ("%g"):format(s) } }
            any = any or items[i].active
        end
        -- Not one of the list: the title says which it is.
        return { type = "suji-speed", title = any and "Speed" or "Speed  " .. short(speed), items = items }
    end,
})

local render = b.render
function b.render(ctx, box, v)
    local out = render(ctx, box, v)
    return label and out .. "\n" .. ctx.badge(label, box, v) or out
end

return b
