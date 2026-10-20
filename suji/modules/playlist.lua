-- Playlist and chapters: the chapters on top and the playlist under them,
-- each with a header; with only one of the two, no headers. Shown when the
-- file has chapters or the playlist has more than one entry.

local base = require "modules.menu_button"
local time = require "modules.time"

local chapters, count = 0, 0 -- the chapters property and playlist-count

-- What to show for a path or URL with no title: its last part, for a URL
-- without the query; the URL itself (the menu cuts it) when it has no path.
-- Plain finds and an anchored match: linear even on a huge name.
local function file_name(s)
    if type(s) ~= "string" then return "" end
    local scheme = s:match("^%a[%w+.-]*://")
    if scheme then
        local q = s:find("[?#]", #scheme + 1)
        if q then s = s:sub(1, q - 1) end
        if not s:find("/", #scheme + 1, true) then return s end
    end
    local last = s:sub(-4096):reverse():match("^[^/\\]*"):reverse()
    return last ~= "" and last or s
end

local function chapter_items(list, items)
    local current = mp.get_property_number("chapter")
    local long = (mp.get_property_number("duration") or 0) >= 3600
    for i, c in ipairs(list) do
        if #items >= base.MAX_ITEMS then break end
        if type(c) == "table" then
            local title = type(c.title) == "string" and c.title ~= "" and c.title or ("Chapter %d"):format(i)
            items[#items + 1] = { title = title, hint = time.format_time(tonumber(c.time), long),
                                  value = { "set", "chapter", ("%d"):format(i - 1) }, active = current == i - 1 }
        end
    end
end

local function playlist_items(list, items)
    for i, e in ipairs(list) do
        if #items >= base.MAX_ITEMS then break end
        if type(e) == "table" then
            local title = type(e.title) == "string" and e.title ~= "" and e.title or file_name(e.filename)
            items[#items + 1] = { title = title, value = { "playlist-play-index", ("%d"):format(i - 1) },
                                  active = e.current == true }
        end
    end
end

local M = base.new({
    icon = "playlist",
    live = { "chapter-list", "chapter", "playlist" },

    init = function(ctx)
        local function update(c, n)
            local before = chapters > 0 or count > 1
            chapters, count = c or chapters, n or count
            if (chapters > 0 or count > 1) ~= before then ctx.relayout() end
        end
        ctx.watch("chapters", "native", function(v) update(tonumber(v) or 0, nil) end)
        ctx.watch("playlist-count", "native", function(v) update(nil, tonumber(v) or 0) end)
    end,

    available = function() return chapters > 0 or count > 1 end,

    build = function()
        local ch = mp.get_property_native("chapter-list")
        local pl = mp.get_property_native("playlist")
        ch = type(ch) == "table" and ch or {}
        pl = type(pl) == "table" and #pl > 1 and pl or {}
        local both, items = #ch > 0 and #pl > 0, {}
        if both then items[1] = base.header("Chapters") end
        chapter_items(ch, items)
        if both then
            items[#items].separator = true
            items[#items + 1] = base.header("Playlist")
        end
        playlist_items(pl, items)
        return { type = "suji-playlist", items = items }
    end,
})

M.file_name = file_name

return M
