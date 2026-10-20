-- Subtitles: Off, the subtitle tracks and, when mpv can read the clipboard,
-- loading a subtitle file whose path or URL is there. Shown whenever a file
-- is loaded, also one with no subtitles: the clipboard can still add one.

local base = require "modules.menu_button"

local idle = false -- idle-active: no file

return base.new({
    icon = "subtitles",
    live = { "track-list" },

    init = function(ctx)
        ctx.watch("idle-active", "native", function(v)
            if (v == true) ~= idle then
                idle = v == true
                ctx.relayout()
            end
        end)
    end,

    available = function() return not idle end,

    build = function()
        local tracks = base.track_items(mp.get_property_native("track-list"), "sub", "sid")
        local on = false
        for _, t in ipairs(tracks) do on = on or t.active end
        local items = { { title = "Off", value = { "set", "sid", "no" }, active = not on } }
        for _, t in ipairs(tracks) do items[#items + 1] = t end
        if base.has_clipboard() then
            items[#items].separator = true
            items[#items + 1] = base.clipboard_item("Load from clipboard", "sub-add")
        end
        return { type = "suji-subtitles", items = items }
    end,
})
