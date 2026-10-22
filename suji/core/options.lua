-- Options from script-opts/suji.conf (read at start) and script-opts (also
-- at run time). Defaults decide each type, so none of them may be nil.

local msg = require "mp.msg"
local draw = require "core.draw"

local DEFAULTS = {
    enabled = true,        -- no = suji draws nothing and leaves the player alone
    idle_line = true,      -- 2 px progress line at rest; no = nothing on screen
    accent = "ffffff",     -- colour of the progress and the knob (rrggbb)
    pause_on_drag = false, -- pause while dragging the timeline
    remaining_time = false, -- show "-13:52" instead of the duration
    hide_delay = 1.5,      -- seconds without mouse movement before hiding
    proximity = 120,       -- distance in px (at scale 1) where the bar reacts
    scale = 1,             -- size factor, multiplied by the system HiDPI scale
                           -- and by the size of the more menu (core/size.lua)
    thumbnails = true,     -- ask thumbfast for thumbnails on the timeline
                           -- (core/thumbnail.lua); no = never talk to it
    debug = false,         -- log sizes and scale to the mpv console
    -- The row everyone sees who installs suji and touches nothing: playback
    -- on the left, under the title; what is changed while watching (the
    -- menus, the volume, fullscreen) together on the right, where opening a
    -- menu never covers the title. Keep docs/suji.conf in step.
    -- Elements, left to right, separated by commas (see core/controls.lua):
    --   pause, time, volume, fullscreen      the controls of v0.1.0
    --   subtitles, audio, playlist, speed, more   buttons with menus;
    --                each one hides, leaving no gap, when it has nothing
    --                to offer
    --   space        takes the free width: what follows goes to the right
    --   gap          a small fixed hole
    --   command:icon:command?text            a button that runs an mpv command
    --   button:name  a button another script defines with set-button
    --                (docs/api.md); no room until it exists
    -- Conditions go before an element, in <...>: video, audio, stream,
    -- has_chapter, has_playlist, idle, or any mpv property or user-data/...
    -- (true when it exists and is not false, no, 0 or empty). "," is OR,
    -- "+" is AND, "!" negates: <video,audio>, <has_playlist+!stream>.
    controls = "pause,time,space,subtitles,audio,playlist,speed,more,volume,fullscreen",
}

-- Numbers are kept in these ranges; NaN falls back to the default.
local LIMITS = { hide_delay = { 0, 3600 }, proximity = { 1, 10000 }, scale = { 0.25, 8 } }

local M = {}

M.LIMITS = LIMITS -- for the size of the more menu, which multiplies scale

local warned -- last invalid accent warned about, not to repeat it

-- The usable value of every option in raw (left untouched), with warnings.
function M.validate(raw)
    local out = {}
    for k, v in pairs(DEFAULTS) do
        out[k] = raw[k]
        if type(out[k]) ~= type(v) then out[k] = v end
    end
    if not draw.color(out.accent) then
        if out.accent ~= warned then
            msg.warn(("invalid accent '%s', using ffffff"):format(draw.printable(out.accent, 32)))
        end
        warned, out.accent = out.accent, DEFAULTS.accent
    else
        warned = nil -- a bad value set again later is warned about again
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
