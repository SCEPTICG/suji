-- Playlist and chapters: the chapters on top and the playlist under them,
-- each with a header; with only one of the two, no headers. The playlist
-- lists only video, audio and URLs (mpv puts every entry of a folder in it,
-- subfolders too), and the current entry whatever it is. Shown when the
-- file has chapters or the playlist has more than one entry to list.

local base = require "modules.menu_button"
local time = require "modules.time"

local TYPE = "suji-playlist"

local chapters, count = 0, 0 -- the chapters property, and entries listed (up to 2)
local MAX_LOOK = 1000 -- entries looked at to count them, one property read each
-- In the menu last built: the item of each chapter (by index from 0), and
-- the chapter marked. A new chapter only moves the mark.
local where, marked = {}, nil

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

-- Whether path is something to play: a URL (with a scheme, ://), or a
-- file with a video or audio extension, in any case (.mkv, .MKV, .flac).
-- Folders and files with no extension are not. The extensions are mpv's
-- video-exts and audio-exts (mpv 0.40), as the user set them; MEDIA when
-- mpv has neither.
local MEDIA = {}
for ext in ([[3g2 3gp avi flv m2ts m4v mj2 mkv mov mp4 mpeg mpg mts ogv rmvb ts vob webm wmv y4m
             aac ac3 aiff alac ape au dts eac3 flac m4a mka mp3 oga ogg ogm opus thd wav wma wv]]):gmatch("%S+") do
    MEDIA[ext] = true
end
local exts = MEDIA
local lists = {} -- the value of video-exts and audio-exts

-- exts from mpv's two lists, read when one of them changes.
local function set_exts(prop, list)
    lists[prop] = type(list) == "table" and list or nil
    if not lists["video-exts"] and not lists["audio-exts"] then
        exts = MEDIA
        return
    end
    exts = {}
    for _, l in pairs(lists) do
        for _, ext in ipairs(l) do
            if type(ext) == "string" then exts[ext:lower()] = true end
        end
    end
end

local function is_media(path)
    if path:find("^%a[%w+.-]*://") then return true end
    -- The extension of the last part only: a folder "show.2024" has none.
    local ext = path:match("%.([^./\\]+)$")
    return ext ~= nil and exts[ext:lower()] == true
end

-- Whether the menu lists entry e: media, or the current one.
local function listed(e)
    return type(e) == "table" and (e.current == true or type(e.filename) == "string" and is_media(e.filename))
end

-- How many entries the menu lists, up to 2: the button only needs to know
-- if there are two. Read entry by entry, never the whole playlist (with
-- thousands of entries that costs mpv a lot), and only the first MAX_LOOK.
local function count_listed()
    local total = mp.get_property_number("playlist-count", 0)
    local current = mp.get_property_number("playlist-current-pos", -1)
    local n = current >= 0 and current < total and 1 or 0
    for i = 0, math.min(total, MAX_LOOK) - 1 do
        if n >= 2 then break end
        if i ~= current then
            local f = mp.get_property(("playlist/%d/filename"):format(i))
            if type(f) == "string" and is_media(f) then n = n + 1 end
        end
    end
    return n
end

local function chapter_items(list, items)
    local current = mp.get_property_number("chapter")
    local long = (mp.get_property_number("duration") or 0) >= 3600
    where, marked = {}, current
    for i, c in ipairs(list) do
        if #items >= base.MAX_ITEMS then break end
        if type(c) == "table" then
            where[i - 1] = #items + 1
            local title = type(c.title) == "string" and c.title ~= "" and c.title or ("Chapter %d"):format(i)
            items[#items + 1] = { title = title, hint = time.format_time(tonumber(c.time), long),
                                  value = { "set", "chapter", ("%d"):format(i - 1) }, active = current == i - 1 }
        end
    end
end

-- The entries listed, with mpv's index of each; the first base.MAX_ITEMS
-- entries are looked at.
local function playlist_items(list)
    local out = {}
    for i, e in ipairs(list) do
        if i > base.MAX_ITEMS then break end
        if listed(e) then
            local title = type(e.title) == "string" and e.title ~= "" and e.title or file_name(e.filename)
            out[#out + 1] = { title = title, value = { "playlist-play-index", ("%d"):format(i - 1) },
                              active = e.current == true }
        end
    end
    return out
end

local M = base.new({
    icon = "playlist",
    live = { "chapter-list", "chapter", "playlist" },

    on_live = function(ctx, prop)
        if prop ~= "chapter" then return false end
        local current = mp.get_property_number("chapter")
        if where[marked] then ctx.mark_menu(TYPE, where[marked], false) end
        if where[current] then ctx.mark_menu(TYPE, where[current], true) end
        marked = current
        return true
    end,

    init = function(ctx)
        local function update(c, n)
            local before = chapters > 0 or count > 1
            chapters, count = c or chapters, n or count
            if (chapters > 0 or count > 1) ~= before then ctx.relayout() end
        end
        ctx.watch("chapters", "native", function(v) update(tonumber(v) or 0, nil) end)
        -- mpv sends several changes of the playlist for one new file: they
        -- are counted once, by a timer armed only when one comes.
        local recount = mp.add_timeout(0, function() update(nil, count_listed()) end, true)
        local function changed() if not recount:is_enabled() then recount:resume() end end
        ctx.watch("playlist", "none", changed)
        for _, prop in ipairs({ "video-exts", "audio-exts" }) do
            ctx.watch(prop, "native", function(v) set_exts(prop, v); changed() end)
        end
    end,

    available = function() return chapters > 0 or count > 1 end,

    build = function()
        local ch = mp.get_property_native("chapter-list")
        local pl = mp.get_property_native("playlist")
        ch = type(ch) == "table" and ch or {}
        pl = playlist_items(type(pl) == "table" and pl or {})
        if #pl < 2 then pl = {} end
        local both, items = #ch > 0 and #pl > 0, {}
        if both then items[1] = base.header("Chapters") end
        chapter_items(ch, items)
        if both then
            items[#items].separator = true
            items[#items + 1] = base.header("Playlist")
        end
        for _, it in ipairs(pl) do
            if #items >= base.MAX_ITEMS then break end
            items[#items + 1] = it
        end
        return { type = TYPE, items = items }
    end,
})

M.file_name = file_name

return M
