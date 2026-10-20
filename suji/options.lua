-- Default options, overridden by script-opts/suji.conf and by
-- --script-opts=suji-<option>=<value>. The type of each default decides
-- how mpv converts the value, so none of them may be nil.

local msg = require "mp.msg"
local draw = require "draw"

local M = {
    idle_line = true,      -- 2 px progress line at rest; no = nothing on screen
    accent = "ffffff",     -- colour of the progress and the knob (rrggbb)
    pause_on_drag = false, -- pause while dragging the timeline
    hide_delay = 1.5,      -- seconds without mouse movement before hiding
    proximity = 120,       -- distance in px (at scale 1) where the bar reacts
    scale = 1,             -- size factor, multiplied by the system HiDPI scale
    debug = false,         -- log sizes and scale to the mpv console
}

require("mp.options").read_options(M, "suji")

if not draw.color(M.accent) then
    msg.warn(("invalid accent '%s', using ffffff"):format(M.accent))
    M.accent = "ffffff"
end
if M.hide_delay < 0 then M.hide_delay = 0 end
if M.proximity < 1 then M.proximity = 1 end

return M
