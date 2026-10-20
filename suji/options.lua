-- Options, read from script-opts/suji.conf and --script-opts=suji-<option>=<value>.
-- They can change while mpv runs (through the script-opts property); the
-- file itself is only read at start-up. The type of each default decides
-- how mpv converts the value, so none of them may be nil.

local msg = require "mp.msg"
local draw = require "draw"

local DEFAULTS = {
    enabled = true,        -- no = suji draws nothing and leaves the player alone
    idle_line = true,      -- 2 px progress line at rest; no = nothing on screen
    accent = "ffffff",     -- colour of the progress and the knob (rrggbb)
    pause_on_drag = false, -- pause while dragging the timeline
    remaining_time = false, -- show "-13:52" instead of the duration
    hide_delay = 1.5,      -- seconds without mouse movement before hiding
    proximity = 120,       -- distance in px (at scale 1) where the bar reacts
    scale = 1,             -- size factor, multiplied by the system HiDPI scale
    debug = false,         -- log sizes and scale to the mpv console
}

-- Numbers are kept in these ranges; NaN falls back to the default.
local LIMITS = { hide_delay = { 0, 3600 }, proximity = { 1, 10000 }, scale = { 0.25, 8 } }

local M = {}

-- The usable value of every option in raw (left untouched), with warnings.
function M.validate(raw)
    local out = {}
    for k, v in pairs(DEFAULTS) do
        out[k] = raw[k]
        if type(out[k]) ~= type(v) then out[k] = v end
    end
    if not draw.color(out.accent) then
        msg.warn(("invalid accent '%s', using ffffff"):format(out.accent))
        out.accent = DEFAULTS.accent
    end
    for k, r in pairs(LIMITS) do
        local v = out[k]
        if v ~= v then v = DEFAULTS[k] end
        out[k] = math.max(r[1], math.min(r[2], v))
    end
    return out
end

-- mpv writes into raw; M only ever holds validated values.
local raw, listener = {}, nil
for k, v in pairs(DEFAULTS) do raw[k] = v end
local function apply() for k, v in pairs(M.validate(raw)) do M[k] = v end end

-- fn(changed) runs after a change at run time; changed[name] is true for
-- each option that changed.
function M.on_update(fn) listener = fn end

require("mp.options").read_options(raw, "suji", function(changed)
    apply()
    if listener then listener(changed) end
end)
apply()

return M
