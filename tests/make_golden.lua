-- Writes the golden output of the current code to the file given as the
-- first argument. Only needed again if the look of suji changes on purpose:
--   LUA_PATH="./suji/?.lua;./tests/?.lua;;" lua5.1 tests/make_golden.lua tests/golden/v0.1.0.txt
local text = require("golden")()
local f = assert(io.open(assert(arg[1], "usage: make_golden.lua <file>"), "wb"))
f:write(text)
f:close()
