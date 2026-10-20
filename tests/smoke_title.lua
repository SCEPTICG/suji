-- Loaded next to suji in the smoke test: sends a two-line title.
mp.register_event("file-loaded", function()
    mp.commandv("script-message-to", "suji", "set-title", "Show", "Episode")
end)
