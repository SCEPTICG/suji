-- A fake thumbfast for the tests in a virtual display (see tests/run.sh):
-- loaded as tests/fake/thumbfast.lua, so mpv calls it "thumbfast" and
-- suji's messages reach it. It does what thumbfast documents for the
-- scripts that use it, and nothing more: once, as it starts, it sends
--   script-message thumbfast-info {"width":160,"height":90,...}
-- (so suji, loaded at the same time, has to hear it then) and it takes
-- the thumb and clear messages. What it gets is kept in
-- user-data/fake-thumbfast = { last, thumbs, clears } for the test to
-- read. With image=<file> (raw BGRA, width x height) it also shows that
-- image where it is asked to, as thumbfast would: for screenshots.

local msg = require "mp.msg"
local utils = require "mp.utils"

local o = { width = 160, height = 90, image = "" }
require("mp.options").read_options(o, "thumbfast")

local got = { last = "", thumbs = 0, clears = 0 }
local function publish() mp.set_property_native("user-data/fake-thumbfast", got) end

mp.commandv("script-message", "thumbfast-info", utils.format_json({
    width = o.width, height = o.height, disabled = false, available = true }))

mp.register_script_message("thumb", function(t, x, y)
    got.last, got.thumbs = ("thumb %s %s %s"):format(t, x, y), got.thumbs + 1
    msg.info(got.last)
    if o.image ~= "" then
        mp.commandv("overlay-add", "1", x, y, o.image, "0", "bgra", tostring(o.width), tostring(o.height),
            tostring(4 * o.width))
    end
    publish()
end)

mp.register_script_message("clear", function()
    got.last, got.clears = "clear", got.clears + 1
    msg.info("clear")
    if o.image ~= "" then mp.commandv("overlay-remove", "1") end
    publish()
end)

publish()
