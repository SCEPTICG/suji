-- Every icon of core/icons.lua at scale 1 (22 px) and scale 2 (44 px),
-- with its name, drawn by a real mpv. Not a test: a sheet to look at,
-- saved to $SUJI_SHEET (icons.png by default). From the repository root:
--   SUJI_SHEET=/tmp/icons.png xvfb-run -a -s "-screen 0 1280x1024x24" \
--     mpv --no-config --vo=x11 --ao=null --geometry=1100x620 --pause \
--     --keep-open=yes --script=tests/icons_sheet.lua \
--     av://lavfi:color=c=gray:size=1100x620:duration=5
package.path = "./suji/?.lua;" .. package.path
local icons = require "core.icons"
local draw = require "core.draw"

local W, H = 1100, 620
local COLS = 6

local function sheet()
    local out = { draw.rect(0, 0, W, H, { color = "&H303030&" }) }
    local names = icons.names()
    for i, name in ipairs(names) do
        local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
        local x, y = 20 + col * 180, 20 + row * 100
        for k, s in ipairs({ 1, 2 }) do
            local cx, cy = x + (k == 1 and 20 or 80), y + 30
            local shape, width = icons.shape(name, cx, cy, 22 * s)
            out[#out + 1] = draw.stroke(shape, width, 1, s)
        end
        out[#out + 1] = draw.text(x, y + 72, 7, name, { font = "sans-serif", size = 13, opacity = 0.8, scale = 1 })
    end
    return table.concat(out, "\n")
end

local overlay = mp.create_osd_overlay("ass-events")
overlay.res_x, overlay.res_y = W, H
overlay.data = sheet()
overlay:update()

mp.add_timeout(1.5, function()
    mp.commandv("screenshot-to-file", os.getenv("SUJI_SHEET") or "icons.png", "window")
    mp.add_timeout(1, function() mp.commandv("quit") end)
end)
