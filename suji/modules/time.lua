-- The time: "09:48 / 23:40", or "09:48 / -13:52" with the remaining time.
-- A click switches between the two. While the cursor is on the timeline
-- it shows the time under the cursor instead of the position, dimmed.

local valid = require("core.state").valid_duration

local M = {}

local SIZE = 15

-- Seconds -> "mm:ss", or "h:mm:ss" when long. Unknown -> dashes.
function M.format_time(t, long)
    if type(t) ~= "number" or t ~= t or math.abs(t) == math.huge then
        return long and "-:--:--" or "--:--"
    end
    local n = math.floor(math.abs(t))
    local sign = (t < 0 and n > 0) and "-" or ""
    if long then
        return ("%s%d:%02d:%02d"):format(sign, math.floor(n / 3600), math.floor(n / 60) % 60, n % 60)
    end
    return ("%s%02d:%02d"):format(sign, math.floor(n / 60), n % 60)
end

-- The time in two parts: "09:48" and " / 23:40" (" / -13:52" with
-- remaining), long form from an hour on. shown replaces the first part.
function M.time_text(time, duration, remaining, shown)
    local known = type(time) == "number" and time == time
    local long = math.max(known and time or 0, valid(duration) and duration or 0) >= 3600
    local right
    if valid(duration) and remaining then
        right = "-" .. M.format_time(math.max(0, math.floor(duration) - math.floor(known and time or 0)), long)
    else
        right = M.format_time(valid(duration) and duration or nil, long)
    end
    return M.format_time(shown or time, long), " / " .. right
end

local function parts(ctx)
    local st = ctx.state
    return M.time_text(st.time, st.duration, st.remaining, ctx.hover_time())
end

local shown = "" -- the time as last drawn

function M.init(ctx)
    -- Repaint when the time shown changes with the controls up.
    local function on_change()
        if not ctx.visible() then return end
        local left, right = M.time_text(ctx.state.time, ctx.state.duration, ctx.state.remaining)
        if left .. right ~= shown then
            shown = left .. right
            return true
        end
    end
    ctx.watch("time-pos", "number", on_change)
    ctx.watch("duration", "number", on_change)
end

-- Digits as zeros, so the width does not change every second.
function M.width(ctx)
    local left, right = parts(ctx)
    return ctx.text_width(((left .. right):gsub("%d", "0")), SIZE)
end

function M.render(ctx, box, v)
    local hover = ctx.hover_time()
    local left, right = parts(ctx)
    return ctx.draw.text(box.x0, box.cy, 4, { { left, hover and 0.6 * v or v }, { right, v } }, ctx.style(SIZE, v))
end

function M.press(ctx)
    local st = ctx.state
    st.remaining = not st.remaining
    if ctx.opts.debug then ctx.log.info("remaining time " .. (st.remaining and "on" or "off")) end
end

return M
