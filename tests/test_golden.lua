-- With the default controls, suji paints the same ASS and clicks land in the
-- same places as in v0.1.0 (tests/golden/v0.1.0.txt, see golden.lua).
local T = require "lib"

local f = assert(io.open("tests/golden/v0.1.0.txt", "rb"))
local want = f:read("*a")
f:close()
local got = require("golden")()

local function lines(s)
    local t = {}
    for l in s:gmatch("([^\n]*)\n") do t[#t + 1] = l end
    return t
end
local a, b = lines(got), lines(want)
local first
for i = 1, math.max(#a, #b) do
    if a[i] ~= b[i] then first = i; break end
end
T.check(first == nil, first and ("same output as v0.1.0, first difference at line %d:\n  got  %s\n  want %s")
    :format(first, tostring(a[first]), tostring(b[first])) or "")
T.eq(#a, #b, "same number of lines")

T.done("test_golden")
