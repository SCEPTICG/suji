-- The size chosen in the more menu: a percentage of the scale option, kept
-- in a file of suji's own, suji-size, which holds the number and nothing
-- else: in mpv's state folder (~~state/) when it exists, else in mpv's
-- config folder (~~home/), since mpv only creates the state folder when it
-- saves something there. Read once at start; written only when a size is
-- chosen, never at rest. A file that is missing, unreadable
-- or holds anything but one of SIZES gives 100%; read and write errors are
-- logged once, and the size chosen still applies until mpv is closed.

local msg = require "mp.msg"
local utils = require "mp.utils"
local draw = require "core.draw"

local M = {}

M.SIZES = { 75, 90, 100, 110, 125, 150 } -- percent
local NAME = "suji-size"
local MAX_READ = 16 -- bytes read from the file
local ENOENT = 2    -- errno of a missing file, the same on Linux, macOS and Windows

local percent = 100
local listener -- fn() after a change
local warned = false

local function valid(n)
    for _, s in ipairs(M.SIZES) do
        if n == s then return true end
    end
    return false
end

local function warn(text)
    if warned then return end
    warned = true
    msg.warn(text)
end

-- The folder that ~~state/ or ~~home/ names, or nil. With --no-config
-- mpv has neither: they expand to "", and the name alone would be relative
-- to the current folder.
local function folder(placeholder)
    local dir = mp.command_native({ "expand-path", placeholder })
    if type(dir) ~= "string" or not (dir:find("^[/\\]") or dir:find("^%a:[/\\]")) then return nil end
    return (dir:gsub("[/\\]+$", ""))
end

local function is_dir(dir)
    local info = dir and utils.file_info(dir)
    return type(info) == "table" and info.is_dir == true
end

-- Where the file is written: the state folder when it exists, else the
-- config folder; nil when mpv has neither. A file read from the config
-- folder while the state folder exists is replaced by the one written
-- there, which is read first.
local function path()
    local dir = folder("~~state/")
    if not is_dir(dir) then dir = folder("~~home/") end
    return dir and dir .. "/" .. NAME
end

-- The file in the state folder, else the one in the config folder: the
-- first that exists. A missing file is the size never chosen: no warning.
-- Only a regular file is opened: a FIFO would block mpv's start.
local function open()
    for _, placeholder in ipairs({ "~~state/", "~~home/" }) do
        local dir = folder(placeholder)
        local p = dir and dir .. "/" .. NAME
        local info = p and utils.file_info(p)
        if info then
            if not info.is_file then
                warn(("size: %s is not a regular file, using 100%%"):format(draw.printable(p, 300)))
                return nil
            end
            local f, err, code = io.open(p, "rb")
            if f then return f, p end
            if code ~= ENOENT then
                warn(("size: cannot read %s, using 100%%"):format(draw.printable(err, 300)))
                return nil
            end
        end
    end
end

-- The size in the file, if it is one of SIZES.
function M.load()
    local f, p = open()
    if not f then return end
    local s = f:read(MAX_READ)
    f:close()
    local n = tonumber(type(s) == "string" and s:match("^%s*(%d+)%s*$") or nil)
    if valid(n) then
        percent = n
    else
        warn(("size: %s holds no size of the list, using 100%%"):format(draw.printable(p, 300)))
    end
end

-- Nothing there, or a regular file: what may be written over.
local function writable(p)
    local info = utils.file_info(p)
    return not info or info.is_file
end

-- Write text to p, which must be writable. True, or nil and the error.
local function write(p, text)
    local f, err = io.open(p, "wb")
    if not f then return nil, err end
    local ok, werr = f:write(text)
    local closed, cerr = f:close()
    if not ok then return nil, werr end
    if not closed then return nil, cerr end
    return true
end

-- Write n to the file, or warn that it cannot. Written to NAME.tmp and
-- renamed over the file, so a symbolic link there is replaced, not
-- followed. Windows does not rename over a file that exists: then it is
-- removed first, and as a last resort written in place.
local function save(n)
    local p = path()
    if not p then return end
    local tmp, text = p .. ".tmp", ("%d\n"):format(n)
    if not writable(p) or not writable(tmp) then
        warn(("size: %s is not a regular file, the size is not saved"):format(draw.printable(p, 300)))
        return
    end
    -- A symbolic link named NAME.tmp would be followed: removed (the link,
    -- not what it points to) before writing. A half write is removed too.
    os.remove(tmp)
    local ok, err = write(tmp, text)
    if not ok then
        os.remove(tmp)
    else
        ok, err = os.rename(tmp, p)
        if not ok then
            os.remove(p)
            ok, err = os.rename(tmp, p)
        end
        if not ok then
            os.remove(tmp)
            ok, err = write(p, text)
        end
    end
    if not ok then warn(("size: cannot save the size: %s"):format(draw.printable(err, 300))) end
end

function M.percent() return percent end

-- The scale option times the size, in the option's range.
function M.scale(user, limits)
    return math.max(limits[1], math.min(limits[2], user * percent / 100))
end

-- Choose n, one of SIZES: it applies at once and is saved.
function M.set(n)
    if not valid(n) then return false end
    percent = n
    save(n)
    if listener then listener() end
    return true
end

function M.on_change(fn) listener = fn end

return M
