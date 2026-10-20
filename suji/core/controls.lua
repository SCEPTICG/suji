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
-- false, "no", 0 or empty.
function M.truthy(v)
    if v == nil or v == false or v == "no" or v == 0 or v == "" then return false end
    return type(v) ~= "table" or next(v) ~= nil
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- "a,b+!c" -> { { factor, ... }, ... }: OR of ANDs. A factor is
-- { prop = name, test = fn, neg = bool }.
local function parse_cond(s)
    local terms = {}
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
            factors[#factors + 1] = { prop = named and named[1] or f, test = named and named[2] or M.truthy, neg = neg }
        end
        terms[#terms + 1] = factors
    end
    return terms
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

-- Every property a list of elements depends on, once each.
function M.props(list)
    local out, seen = {}, {}
    for _, it in ipairs(list) do
        for _, factors in ipairs(it.cond or {}) do
            for _, f in ipairs(factors) do
                if not seen[f.prop] then seen[f.prop] = true; out[#out + 1] = f.prop end
            end
        end
    end
    return out
end

-- One element -> { kind = "space" | "gap" | "module" | "command", ... } or
-- nil and the reason. known[name] is true for the modules of the row.
local function parse_item(raw, known)
    local cond, err
    if raw:sub(1, 1) == "<" then
        local close = raw:find(">", 2, true)
        if not close then return nil, "no closing >" end
        cond, err = parse_cond(raw:sub(2, close - 1))
        if not cond then return nil, err end
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
        return { kind = "command", icon = icon, command = command, text = text, cond = cond }
    end
    if name == "button" then return nil, "button: is not supported yet" end
    if rest ~= "" then return nil, "unexpected '" .. rest .. "'" end
    if name == "space" or name == "gap" then return { kind = name, cond = cond } end
    if known[name] then return { kind = "module", name = name, cond = cond } end
    return nil, "unknown element"
end

-- The option string -> list of elements. warn(text) gets one line per
-- skipped element, already safe to print.
function M.parse(s, known, warn)
    if type(s) ~= "string" then return {} end
    if #s > M.MAX_BYTES then
        warn(("controls: longer than %d bytes, the rest is ignored"):format(M.MAX_BYTES))
        s = s:sub(1, M.MAX_BYTES)
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
