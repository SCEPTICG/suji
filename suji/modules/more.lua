-- More: the video track (when there is more than one), the editions (when
-- there is more than one; choosing one restarts playback), opening the
-- file or URL in the clipboard when mpv can read it, and the size of suji
-- (core/size.lua). Size turns the same menu into the list of sizes, and a
-- size applies at once with the menu still open. Shown whenever a file is
-- loaded.

local base = require "modules.menu_button"
local size = require "core.size"

local MAX_EDITIONS = 500

local idle = false -- idle-active: no file
local page         -- "size" while the menu lists the sizes, else nil

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

local build

-- The sizes, the current one marked. A choice keeps the menu open and
-- moves the mark. first: the list replaces the first one, and a cursor of
-- the keys goes to the current size.
local function sizes(ctx, first)
    local items, current = {}, nil
    for i, n in ipairs(size.SIZES) do
        items[i] = { title = ("%d%%"):format(n), active = n == size.percent(), keep_open = true, action = function()
            size.set(n)
            ctx.update_menu(build(ctx))
        end }
        if items[i].active then current = i end
    end
    return { type = "suji-more", title = "Size", items = items, selected_index = first and current or nil }
end

function build(ctx)
    if page == "size" then return sizes(ctx) end
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
    if #items > 0 then items[#items].separator = true end
    items[#items + 1] = { title = "Size", hint = ("%d%%"):format(size.percent()), keep_open = true, action = function()
        page = "size"
        ctx.update_menu(sizes(ctx, true))
    end }
    return { type = "suji-more", items = items }
end

local b = base.new({
    icon = "more",
    live = { "track-list", "edition-list", "current-edition" },

    init = function(ctx)
        ctx.watch("idle-active", "native", function(v)
            if (v == true) ~= idle then
                idle = v == true
                ctx.relayout()
            end
        end)
    end,

    available = function() return not idle end,

    build = build,
})

-- Opened again, it starts from the first list.
local menu_closed = b.menu_closed
function b.menu_closed(ctx)
    page = nil
    menu_closed(ctx)
end

return b
