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
    -- and the volume on the left, the menus and fullscreen on the right.
    -- Keep docs/suji.conf in step.
    -- Elements, left to right, separated by commas (see core/controls.lua):
    --   pause, time, volume, fullscreen      the controls of v0.1.0; the
    --                volume's slider unfolds with the cursor on the speaker
    --   prev, next   the previous and the next entry of the playlist;
    --                shown with more than one, each one hides, leaving no
    --                gap, at its end of the playlist
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
    -- A row of OLD_ROWS (below) counts as not set: this one is used.
    controls = "pause,prev,next,volume,time,space,subtitles,audio,playlist,speed,more,fullscreen",
}

-- Default rows of older versions. docs/suji.conf used to set every option,
-- so whoever copied it kept that version's row without ever choosing it:
-- such a row, exactly (only spaces around it may differ: a line ending in
-- \r from Windows, say), counts as not set and the current default is
-- used. Any other change, in the order or an element, keeps it.
local OLD_ROWS = {
    -- 0.2.0 to 0.6.1 (0.1.0 had no controls option)
    "pause,time,space,subtitles,audio,playlist,speed,more,volume,fullscreen",
}

-- Numbers are kept in these ranges; NaN falls back to the default.
local LIMITS = { hide_delay = { 0, 3600 }, proximity = { 1, 10000 }, scale = { 0.25, 8 } }

local M = {}

M.LIMITS = LIMITS -- for the size of the more menu, which multiplies scale

local warned -- last invalid accent warned about, not to repeat it
local old_row -- an old row was recognised the last time, not to log it again

-- True when s is one of OLD_ROWS. Long strings are not even trimmed.
local function is_old_row(s)
    if #s > 256 then return false end
    s = s:match("^%s*(.-)%s*$")
    for _, row in ipairs(OLD_ROWS) do
        if s == row then return true end
    end
    return false
end

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
    if is_old_row(out.controls) then
        if out.debug and not old_row then
            msg.info("controls: the default row of suji 0.2.0 to 0.6.1, the current default is used"
                .. " (change anything in it to keep it)")
        end
        old_row, out.controls = true, DEFAULTS.controls
    else
        old_row = nil
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
