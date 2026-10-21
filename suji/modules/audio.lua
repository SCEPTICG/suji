-- Audio: the audio tracks. Shown when there is more than one to choose.

local base = require "modules.menu_button"

local tracks = 0 -- audio tracks

return base.new({
    icon = "audio",
    live = { "track-list" },

    -- track-list and not track-list/count: a new file with as many tracks
    -- of other types would keep the count and not be noticed.
    init = function(ctx)
        ctx.watch("track-list", "native", function(list)
            local before = tracks > 1
            tracks = base.count(list, "audio")
            if (tracks > 1) ~= before then ctx.relayout() end
        end)
    end,

    available = function() return tracks > 1 end,

    build = function()
        return { type = "suji-audio", items = base.track_items(mp.get_property_native("track-list"), "audio", "aid") }
    end,
})
