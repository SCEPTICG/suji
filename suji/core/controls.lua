-- The controls option: which elements the row shows, in which order and
-- under which conditions. Parsing and evaluating are pure; the caller
-- watches the properties the conditions name. See docs/suji.conf.
--
--   controls=pause,time,space,<video,audio>command:x:cycle sub?Subtitles,volume
--
-- Each element is [<conditions>]name[:parameters][?text], separated by
-- commas; commas inside <...> do not separate elements. Conditions: "," is
-- OR, "+" is AND and "!" negates one name. "!" binds tightest, then "+",
-- then ",": <a,b+!c> means a OR (b AND NOT c).

local draw = require "core.draw"

local M = {}

M.MAX_BYTES = 4096 -- longer strings are cut (they may come from script-opts)
M.MAX_ITEMS = 32

-- Named conditions: the property behind each one and when it holds.
local NAMED = {
    video = { "current-tracks/video", function(v) return type(v) == "table" and not v.albumart end },
    audio = { "current-tracks/audio", function(v) return type(v) == "table" end },
    stream = { "demuxer-via-network", function(v) return v == true end },
    has_chapter = { "chapters", function(v) return (tonumber(v) or 0) > 0 end },
    has_playlist = { "playlist-count", function(v) return (tonumber(v) or 0) > 1 end },
    idle = { "idle-active", function(v) return v == true end },
}

-- Any other property (or user-data/...) holds when it exists and is not
-- false, "no", 0 or empty. Strings too: "false" and "0" (set user-data/x 0
-- from input.conf gives a string).
local FALSE = { [false] = true, no = true, ["false"] = true, [0] = true, ["0"] = true, [""] = true }
function M.truthy(v)
    if v == nil or FALSE[v] then return false end
    return type(v) ~= "table" or next(v) ~= nil
end

-- Linear in the length, also for a long run of spaces.
local function trim(s)
    local i = s:find("%S")
    return i and s:match("^.*%S", i) or ""
end

-- "a,b+!c" -> { { factor, ... }, ... }: OR of ANDs, and the properties it
-- names, once each. A factor is { prop = name, test = fn, neg = bool }.
local function parse_cond(s)
    local terms, props, seen = {}, {}, {}
    for term in (s .. ","):gmatch("([^,]*),") do
        local factors = {}
        for f in (term .. "+"):gmatch("([^+]*)%+") do
            f = trim(f)
            local neg = f:sub(1, 1) == "!"
            if neg then f = trim(f:sub(2)) end
            if not f:match("^[%w_%-/]+$") or #f > 128 then
                return nil, "bad condition '" .. f .. "'"
            end
            local named = NAMED[f]
            local prop = named and named[1] or f
            factors[#factors + 1] = { prop = prop, test = named and named[2] or M.truthy, neg = neg }
            if not seen[prop] then seen[prop] = true; props[#props + 1] = prop end
        end
        terms[#terms + 1] = factors
    end
    return terms, props
end

-- true when cond holds; values[prop] is the last value seen of each property.
function M.eval(cond, values)
    for _, factors in ipairs(cond) do
        local all = true
        for _, f in ipairs(factors) do
            if f.test(values[f.prop]) == f.neg then all = false; break end
        end
        if all then return true end
    end
    return false
end

-- One element -> { kind = "space" | "gap" | "module" | "command", cond,
-- props, ... } or nil and the reason. props: the properties cond names.
-- known[name] is true for the modules of the row.
local function parse_item(raw, known)
    local cond, props
    if raw:sub(1, 1) == "<" then
        local close = raw:find(">", 2, true)
        if not close then return nil, "no closing >" end
        cond, props = parse_cond(raw:sub(2, close - 1))
        if not cond then return nil, props end
        raw = trim(raw:sub(close + 1))
    end
    local name, rest = raw:match("^([%w_]+)(.*)$")
    if not name then return nil, "not an element" end
    if name == "command" then
        local icon, command = rest:match("^:([%w_]+):(.*)$")
        if not icon then return nil, "use command:icon:command" end
        local q = command:find("?", 1, true)
        local text
        if q then command, text = command:sub(1, q - 1), command:sub(q + 1) end
        command = trim(command)
        if command == "" then return nil, "empty command" end
        return { kind = "command", icon = icon, command = command, text = text, cond = cond, props = props }
    end
    if name == "button" then return nil, "button: is not supported yet" end
    if rest ~= "" then return nil, "unexpected '" .. rest .. "'" end
    if name == "space" or name == "gap" then return { kind = name, cond = cond, props = props } end
    if known[name] then return { kind = "module", name = name, cond = cond, props = props } end
    return nil, "unknown element"
end

-- The option string -> list of elements. warn(text) gets one line per
-- skipped element, already safe to print.
function M.parse(s, known, warn)
    if type(s) ~= "string" then return {} end
    if #s > M.MAX_BYTES then
        warn(("controls: longer than %d bytes, the rest is ignored"):format(M.MAX_BYTES))
        -- Without the element cut in half, unless the cut falls on a comma.
        local cut = s:sub(1, M.MAX_BYTES)
        s = s:sub(M.MAX_BYTES + 1, M.MAX_BYTES + 1) == "," and cut or (cut:match("^(.*),") or "")
    end
    local out, n, i = {}, 0, 1
    while i <= #s do
        local j = s:find("%S", i)
        if not j then break end
        -- A comma ends the element, unless it is inside its leading <...>.
        local from = j
        if s:sub(j, j) == "<" then from = s:find(">", j, true) or #s end
        local comma = s:find(",", from, true) or #s + 1
        local raw = trim(s:sub(j, comma - 1))
        i = comma + 1
        if raw ~= "" then
            if n == M.MAX_ITEMS then
                warn(("controls: more than %d elements, the rest is ignored"):format(M.MAX_ITEMS))
                break
            end
            n = n + 1
            local item, why = parse_item(raw, known)
            if item then out[#out + 1] = item
            else warn(("controls: skipped '%s': %s"):format(draw.printable(raw, 64), draw.printable(why, 80))) end
        end
    end
    return out
end

return M
