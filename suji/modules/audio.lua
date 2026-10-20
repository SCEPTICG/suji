-- Audio: the audio tracks and, under a header, the audio devices. Shown
-- when there is something to choose: more than one track, or more than
-- one device besides auto. mpv does not say which device auto picked, so
-- with audio-device=auto the "Auto" entry is the one marked.

local base = require "modules.menu_button"

local MAX_DEVICES = 200

local tracks, devices = 0, 0 -- audio tracks, and devices other than auto

local function shown() return tracks > 1 or devices > 1 end

return base.new({
    icon = "audio",
    live = { "track-list", "audio-device-list", "audio-device" },

    -- track-list and not track-list/count: a new file with as many tracks
    -- of other types would keep the count and not be noticed.
    init = function(ctx)
        local function update(t, d)
            local before = shown()
            tracks, devices = t or tracks, d or devices
            if shown() ~= before then ctx.relayout() end
        end
        ctx.watch("track-list", "native", function(list) update(base.count(list, "audio"), nil) end)
        ctx.watch("audio-device-list", "native", function(list)
            local n = 0
            for _, d in ipairs(type(list) == "table" and list or {}) do
                if type(d) == "table" and d.name ~= "auto" then n = n + 1 end
            end
            update(nil, n)
        end)
    end,

    available = shown,

    build = function()
        local items = base.track_items(mp.get_property_native("track-list"), "audio", "aid")
        if #items > 0 then items[#items].separator = true end
        items[#items + 1] = base.header("Devices")
        local current = mp.get_property("audio-device")
        local list = mp.get_property_native("audio-device-list")
        local n = 0
        for _, d in ipairs(type(list) == "table" and list or {}) do
            if n >= MAX_DEVICES then break end
            if type(d) == "table" and type(d.name) == "string" and d.name ~= "" then
                n = n + 1
                local desc = type(d.description) == "string" and d.description ~= "" and d.description or d.name
                items[#items + 1] = { title = d.name == "auto" and "Auto" or desc, active = d.name == current,
                                      value = { "set", "audio-device", d.name } }
            end
        end
        return { type = "suji-audio", items = items }
    end,
})
