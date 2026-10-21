local T = require "lib"
local draw = require "core.draw"
local animation = require "core.animation"

-- Colours and alpha
T.eq(draw.color("ffffff"), "&HFFFFFF&", "white")
T.eq(draw.color("ff8000"), "&H0080FF&", "rgb becomes bgr")
T.eq(draw.color("#12abEF"), "&HEFAB12&", "leading # and mixed case")
T.eq(draw.color("fff"), nil, "short hex is rejected")
T.eq(draw.color("zzzzzz"), nil, "non-hex is rejected")
T.eq(draw.color(nil), nil, "nil is rejected")
T.eq(draw.alpha(1), "&H00&", "opaque")
T.eq(draw.alpha(0), "&HFF&", "transparent")
T.eq(draw.alpha(0.5), "&H80&", "half")
T.eq(draw.alpha(2), "&H00&", "clamped above")
T.eq(draw.alpha(-1), "&HFF&", "clamped below")
T.eq(draw.alpha(0 / 0), "&HFF&", "NaN is transparent")

-- Scale
T.eq(draw.scale(2, 1), 2, "hidpi 2")
T.eq(draw.scale(1.5, 2), 3, "hidpi times option")
T.eq(draw.scale(nil, 1), 1, "missing hidpi")
T.eq(draw.scale(0, 1), 1, "zero hidpi")
T.eq(draw.scale(1, -3), 1, "negative option")

-- Shapes: \p3 means coordinates are multiplied by 4
local r = draw.rect(0, 718, 1280, 720, { color = "&HFFFFFF&", opacity = 1 })
T.check(r:find("\\an7\\pos(0,0)", 1, true) ~= nil, "rect is anchored top-left")
T.check(r:find("\\p3}m 0 2872 l 5120 2872 l 5120 2880 l 0 2880{\\p0}", 1, true) ~= nil,
    "rect path in quarter pixels")
T.check(not r:find("\n"), "one event per shape")
local c = draw.circle(10, 10, 5, { color = "&H000000&", opacity = 0.5, blur = 1 })
T.check(c:find("\\blur1", 1, true) ~= nil, "circle carries blur")
T.check(c:find("m 40 20 b ", 1, true) ~= nil, "circle starts at the top")
local _, curves = c:gsub(" b ", "")
T.eq(curves, 4, "circle uses four curves")

-- Animation
local tw = animation.new(0.2)
T.eq(animation.value(tw, 0), 0, "starts at initial value")
animation.set_target(tw, 1, 10)
T.eq(animation.value(tw, 10), 0, "no jump at start")
T.check(animation.value(tw, 10.1) > 0.5, "ease out passes half before half time")
T.eq(animation.value(tw, 10.2), 1, "reaches target on time")
T.check(animation.running(tw, 10.1), "running mid way")
T.check(not animation.running(tw, 10.3), "stopped after duration")
animation.set_target(tw, 1, 11)
T.eq(tw.start, 10, "same target does not restart")
animation.set_target(tw, 0, 11)
T.near(animation.value(tw, 11), 1, "reverse starts from current value")
local zero = animation.new(0)
animation.set_target(zero, 1, 5)
T.eq(animation.value(zero, 5), 1, "zero duration is instant")

-- printable: only valid UTF-8 passes
local P = draw.printable
T.eq(P("a\195\169b"), "a\195\169b", "2 bytes: é")
T.eq(P("\226\130\172"), "\226\130\172", "3 bytes: €")
T.eq(P("\240\159\152\128"), "\240\159\152\128", "4 bytes: an emoji")
T.eq(P("\244\143\191\191"), "\244\143\191\191", "U+10FFFF, the last one")
T.eq(P("\237\159\191"), "\237\159\191", "U+D7FF, just before the surrogates")
T.eq(P("\192\175"), "??", "overlong 2 bytes (C0)")
T.eq(P("\224\128\175"), "???", "overlong 3 bytes (E0 80)")
T.eq(P("\224\159\191"), "???", "overlong 3 bytes (E0 9F)")
T.eq(P("\240\128\128\175"), "????", "overlong 4 bytes (F0 80)")
T.eq(P("\240\143\191\191"), "????", "overlong 4 bytes (F0 8F)")
T.eq(P("\237\160\128"), "???", "surrogate U+D800")
T.eq(P("\237\191\191"), "???", "surrogate U+DFFF")
T.eq(P("\244\144\128\128"), "????", "over U+10FFFF (F4 90)")
T.eq(P("\245\128\128\128"), "????", "F5")
T.eq(P("x\194\133y"), "x??y", "C1 control (U+0085)")
T.eq(P("\128a"), "?a", "a stray continuation byte")

T.done("test_draw")
