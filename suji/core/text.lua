-- Text helpers that do not depend on the locale: UTF-8 length and cuts,
-- capitals and fitting a line in a width. No mpv dependencies.

local M = {}

local ELLIPSIS = "\226\128\166"

-- Byte after the character at byte i: a lead byte takes up to three
-- continuation bytes, any other byte (stray ones too) stands alone. So a
-- character is never split, and n characters are at most 4n bytes.
local function next_char(s, i)
    local j = i + 1
    if s:byte(i) >= 192 then
        while j <= i + 3 and (s:byte(j) or 0) >= 128 and s:byte(j) < 192 do j = j + 1 end
    end
    return j
end

function M.len(s)
    local i, n = 1, 0
    while i <= #s do i, n = next_char(s, i), n + 1 end
    return n
end

function M.prefix(s, n)
    local i = 1
    for _ = 1, n do
        if i > #s then break end
        i = next_char(s, i)
    end
    return s:sub(1, i - 1)
end

-- Capitals without depending on the locale: ASCII, Latin-1 letters and the
-- long vowels of romanised Japanese (ā ē ī ō ū).
local MACRONS = { ["\196\129"] = "\196\128", ["\196\147"] = "\196\146", ["\196\171"] = "\196\170",
                  ["\197\141"] = "\197\140", ["\197\171"] = "\197\170" }
function M.upper(s)
    s = s:gsub("[a-z]", function(c) return string.char(c:byte() - 32) end)
    s = s:gsub("\195([\160-\190])", function(c)
        if c == "\183" then return nil end -- division sign
        return "\195" .. string.char(c:byte() - 32)
    end)
    return (s:gsub("[\196\197][\128-\191]", MACRONS))
end

-- text, or its longest prefix plus "…" that is at most max_w wide. Every
-- result has been measured.
function M.fit(text, max_w, width_of)
    if max_w <= 0 then return "" end
    if width_of(text) <= max_w then return text end
    local lo, hi = 0, M.len(text) - 1
    while lo < hi do
        local mid = math.ceil((lo + hi) / 2)
        if width_of(M.prefix(text, mid) .. ELLIPSIS) <= max_w then lo = mid else hi = mid - 1 end
    end
    local cut = (M.prefix(text, lo):gsub("%s+$", "")) .. ELLIPSIS
    if lo == 0 and width_of(cut) > max_w then return "" end
    return cut
end

-- The title to show: media-title, without the extension when mpv fell back
-- to the file name (a file with no title tag).
function M.file_title(media_title, filename, no_ext)
    if media_title == filename and type(no_ext) == "string" and no_ext ~= "" then return no_ext end
    return media_title
end

return M
