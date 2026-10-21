-- More: the video track (when there is more than one), the editions (when
-- there is more than one; choosing one restarts playback) and, when mpv
-- can read the clipboard, opening the file or URL that is there. Shown
-- when a file is loaded and there is one of those to choose.

local base = require "modules.menu_button"

local MAX_EDITIONS = 500

-- idle-active (no file), the video tracks and the editions there are.
local idle, videos, editions = false, 0, 0

local function editions_items(items)
    local list = mp.get_property_native("edition-list")
    if type(list) ~= "table" or #list < 2 then return end
    local current = mp.get_property_number("current-edition")
    items[#items + 1] = base.header("Editions")
    for i, e in ipairs(list) do
        if i > MAX_EDITIONS then break end
        local id = type(e) == "table" and tonumber(e.id)
        if id then
            local title = type(e.title) == "string" and e.title ~= "" and e.title or ("Edition %d"):format(id + 1)
            items[#items + 1] = { title = title, hint = "restarts", active = id == current,
                                  value = { "set", "edition", ("%d"):format(id) } }
        end
    end
end

-- Something to choose: a video track or an edition, or the clipboard.
local function available()
    return not idle and (videos > 1 or editions > 1 or base.has_clipboard())
end

return base.new({
    icon = "more",
    live = { "track-list", "edition-list", "current-edition" },

    init = function(ctx)
        local function watch(prop, set)
            ctx.watch(prop, "native", function(v)
                local before = available()
                set(v)
                if available() ~= before then ctx.relayout() end
            end)
        end
        watch("idle-active", function(v) idle = v == true end)
        watch("track-list", function(v) videos = base.count(v, "video") end)
        watch("edition-list/count", function(v) editions = tonumber(v) or 0 end)
    end,

    available = available,

    build = function()
        local items = {}
        local video = base.track_items(mp.get_property_native("track-list"), "video", "vid")
        if #video > 1 then
            items[1] = base.header("Video")
            for _, t in ipairs(video) do items[#items + 1] = t end
        end
        editions_items(items)
        if base.has_clipboard() then
            if #items > 0 then items[#items].separator = true end
            items[#items + 1] = base.clipboard_item("Open from clipboard", "loadfile", "replace")
        end
        return { type = "suji-more", items = items }
    end,
})
