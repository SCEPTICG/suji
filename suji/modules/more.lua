-- More: the video track (when there is more than one), the editions (when
-- there is more than one; choosing one restarts playback), the speed and,
-- when mpv can read the clipboard, opening the file or URL that is there.
-- Shown whenever mpv is not idle with no file.

local base = require "modules.menu_button"

local SPEEDS = { 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 3, 4 }
local MAX_EDITIONS = 500

local idle = false -- idle-active: no file

local function editions(items)
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

local function speeds(items)
    local speed = mp.get_property_number("speed") or 1
    local header = base.header("Speed")
    items[#items + 1] = header
    local any = false
    for _, s in ipairs(SPEEDS) do
        local on = math.abs(speed - s) < 0.001
        any = any or on
        items[#items + 1] = { title = ("%g\195\151"):format(s), active = on, value = { "set", "speed", ("%g"):format(s) } }
    end
    if not any then header.hint = ("%g\195\151"):format(math.floor(speed * 100 + 0.5) / 100) end
end

return base.new({
    icon = "more",
    live = { "track-list", "edition-list", "current-edition", "speed" },

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
        local items = {}
        local video = base.track_items(mp.get_property_native("track-list"), "video", "vid")
        if #video > 1 then
            items[1] = base.header("Video")
            for _, t in ipairs(video) do items[#items + 1] = t end
        end
        editions(items)
        speeds(items)
        if base.has_clipboard() then
            items[#items].separator = true
            items[#items + 1] = base.clipboard_item("Open from clipboard", "loadfile", "replace")
        end
        return { type = "suji-more", items = items }
    end,
})
