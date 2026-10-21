# suji for script authors

Other mpv scripts can open menus in suji, put their own buttons in its row and show action buttons above it, with script messages. This page lists what suji understands.

**The API is at 0.x and may still change.** The message and field names follow the ones uosc uses, so a script written for uosc needs few changes to work with suji too. That is the only link: suji is a separate project, written from scratch, and it understands a small part of what uosc does.

Every message goes to the script called `suji`:

```
script-message-to suji <message> <arguments...>
```

From Lua, `mp.commandv("script-message-to", "suji", ...)`.

## Messages

| Message | Arguments | What it does |
| --- | --- | --- |
| `open-menu` | `<json> [anchor]` | Opens a menu (see [The menu](#the-menu)). |
| `update-menu` | `<json>` | Replaces the open menu, if it has the same `type` and was opened with `open-menu`. Otherwise it does nothing: it never opens a menu, and it never touches suji's own menus. |
| `close-menu` | `[type]` | Closes the open menu, any menu; with `type`, only if the open menu has that type. |
| `set-button` | `<name> <json>` | Creates or changes a button (see [Buttons](#buttons)). |
| `show-action` | `<id> <json>` | Shows an action button, or changes it (see [Action buttons](#action-buttons)). |
| `hide-action` | `[id]` | Hides that action button; with no `id`, all of them. |
| `set-title` | `<series> <episode>` | The title, see the README. |

`open-menu` and `update-menu` differ in how the change looks: `open-menu` unfolds the menu from its button, `update-menu` swaps the items at once and keeps the scroll, so it suits a menu whose data changes while it is open. An `open-menu` with the type of a menu that a script opened and is still open works like `update-menu`.

Only one menu is open at a time. Opening a menu closes the one that was open, suji's own too. While suji is turned off (`enabled=no`), `open-menu` does nothing.

### Where the menu comes out

1. From the element of the row named by the `anchor` argument, or by an `anchor` field in the JSON: `subtitles`, `audio`, `playlist`, `speed`, `more`, `command:<icon>`, `button:<name>`. It has to be in the row as it is shown now.
2. Otherwise, from the `command:` or `button:` button the user clicked, if that was less than a second before. This is the usual case: a button runs `script-binding myscript/open-menu`, and the script answers with `open-menu`, without knowing where its button is.
3. Otherwise, from the `more` button, if it is in the row.
4. Otherwise, from the middle of the window, above the row.

The menu follows its button when the row changes. If the button leaves the row, the menu stays open and moves to the middle.

## The menu

```json
{
  "type": "myscript-speed",
  "title": "Speed",
  "items": [
    { "title": "Playback speed", "selectable": false, "muted": true, "italic": true, "align": "center" },
    { "title": "Normal", "hint": "1x", "active": true,
      "value": ["script-message-to", "myscript", "speed", "1"] },
    { "title": "Faster", "hint": "1.5x",
      "value": ["script-message-to", "myscript", "speed", "1.5"] }
  ]
}
```

The menu:

| Field | Type | |
| --- | --- | --- |
| `type` | string | Names the menu, for `update-menu`, `close-menu` and `user-data/suji/menu/type`. At most 64 bytes. Without it, the type is `""`. |
| `title` | string | A small line above the items. |
| `items` | list | The items, at most 50 000; the rest are left out. |
| `selected_index` | number | The item the keyboard cursor starts on and the list scrolls to, counted from 1 over all the items, headings too. Without it, the first active item, else the first. |
| `keep_open` | boolean | Choosing an item does not close the menu. An `update-menu` keeps the keyboard cursor and the highlight on the same line, even when every text changes. |
| `anchor` | string | Where the menu comes out, see above. |

An item:

| Field | Type | |
| --- | --- | --- |
| `title` | string | The text. Cut to 200 characters, and to the width of the menu. |
| `hint` | string | A second, dimmer text on the right. At most 64 characters. |
| `icon` | string | The name of one of suji's icons, see [Icons](#icons). |
| `value` | list or string | The mpv command run when the item is chosen. See below. |
| `active` | boolean | A mark in the accent colour: the current choice. A number counts too, any but 0 being true. |
| `selectable` | boolean | `false`: the item cannot be chosen; it is drawn dimmed and the arrow keys skip it. With no `value`, it is a heading. |
| `muted` | boolean | Dimmer text. |
| `italic`, `bold` | boolean | |
| `separator` | boolean | A thin line under the item. |
| `keep_open` | boolean | Choosing this item does not close the menu. |
| `align` | string | `left` (the default), `center` or `right`. |

Fields suji does not know are ignored, without a warning. So is an item field of the wrong type, and the menu's `title`, `selected_index` and `keep_open`: suji uses the default instead. But a menu whose `type` is not a string or is longer than 64 bytes, or whose `items` is not a list, is not opened at all, with one warning. Texts are cut, control characters are replaced and braces and backslashes are shown as they are, never read as ASS tags.

### value

- **A list of strings** is run with `mp.commandv`: each string is one argument, exactly as it is. This is the safe form, and the one to use.
- **A string** is run with `mp.command`, as a line of `input.conf` would be: `;` separates commands and `${...}` is replaced by the value of a property. suji accepts it because any script that can send the message can run that command itself. But never build such a string from text you do not control, a file name, a title or a path: that text could carry commands of its own. Put it in a list instead.

At most 64 arguments of 8192 bytes each. A value that is empty, too long or not made of strings is dropped, and choosing the item then only closes the menu.

### Getting the user's choice back

suji has no callback of its own: a choice runs the item's `value`. To hear about it, make that value a message to your own script:

```lua
value = { "script-message-to", mp.get_script_name(), "speed", "1.5" }
```

and register it with `mp.register_script_message("speed", ...)`.

## Buttons

```
script-message-to suji set-button <name> <json>
```

```json
{ "icon": "star", "command": ["script-binding", "myscript/open-menu"], "active": true, "badge": "3" }
```

| Field | Type | |
| --- | --- | --- |
| `icon` | string | One of suji's icons. For any other name the button shows its first letter; without an icon, the first letter of the button's name. |
| `command` | list or string | Run when the button is clicked, with the same rules as `value` above. |
| `active` | boolean | A short line in the accent colour under the icon. A number counts too. |
| `badge` | string or number | A short text in the top right corner of the icon, at most 3 characters. |
| `hide` | boolean | The button leaves the row and leaves no gap. |
| `tooltip` | string | Kept, not shown: suji has no tooltips. |

The button appears where the user puts `button:<name>` in the `controls` option, for example:

```
controls=pause,time,space,button:myscript,subtitles,audio,playlist,speed,more,volume,fullscreen
```

A `button:` in `controls` takes no room until a script sets it, and conditions in `<...>` work as with any element. Each `set-button` replaces all the fields of that button: send all of them each time. A `set-button` that changes nothing does not redraw anything.

The name is made of letters, digits, `_` and `-`, at most 64 of them. suji keeps at most 64 buttons; a `set-button` for a 65th name is ignored with a warning.

## Action buttons

A button with a text, above the row on the right, for as long as a script needs it: "Skip opening ›", "Next episode ›". suji draws it like its menus, and runs its command when it is clicked.

```
script-message-to suji show-action <id> <json>
script-message-to suji hide-action [id]
```

```json
{ "text": "Skip opening ›", "command": ["script-message-to", "myscript", "skip", "op"] }
```

| Field | Type | |
| --- | --- | --- |
| `text` | string | Required. One line of at most 64 bytes, cut between characters; control characters show as `?`. The arrow, if you want one, goes in the text. |
| `command` | list or string | Run when the button is clicked, with the same rules as `value` in menus. |

- **Where:** its bottom 12 px above `user-data/suji/margins.bottom`, its right edge at the right margin of the row. Several go in a line from right to left, in the order they were first shown. At most 4 are on screen at a time; the others wait until one of those is hidden.
- **Always on screen**, also while the controls are hidden: a skip should not need a mouse move first.
- **Not while a menu is open.** The buttons fade out and come back when the menu closes.
- **A click** runs the command, once: the second click of a double click runs nothing. The button stays: hide it with `hide-action` once the action is done, since only your script knows when that is.
- **A new file** removes them all, as with menus opened by `open-menu`.
- **While suji is turned off** (`enabled=no`), `show-action` does nothing, and turning suji off removes the buttons it had. They do not come back when suji is turned on again: when `user-data/suji/enabled` turns `true`, send `show-action` again for each button that is still needed.
- **The mouse:** suji only takes the clicks that land on a button on screen.

Each `show-action` replaces all the fields of that button: send all of them each time. A `show-action` that changes nothing does not redraw anything. The id follows the rules of a `set-button` name: letters, digits, `_` and `-`, at most 64 of them. suji keeps at most 16 action buttons; a `show-action` for a 17th id is ignored with a warning, and so is one without a text.

## Knowing when a menu is open

suji publishes the type of the open menu, any menu, in the property `user-data/suji/menu/type`, and deletes it when the menu closes, whatever closes it: a choice, Esc, a click outside, `close-menu`, turning suji off. When another menu takes its place, the property takes the new type, without being deleted in between. On a choice, the item's `value` runs first, and then the menu closes and the property is deleted.

A menu opened with `open-menu` closes when mpv moves to another file, since it was about the old one; suji's own menus stay open and show the new file. suji's own menus are `suji-subtitles`, `suji-audio`, `suji-playlist`, `suji-speed` and `suji-more`.

```lua
mp.observe_property("user-data/suji/menu/type", "native", function(_, t)
    -- t is the type of the open menu, or nil when none is open
end)
```

## Where the controls are

For a script that draws its own things near the bottom of the window, suji publishes `user-data/suji/margins`:

```lua
{ bottom = 62 } -- px, at scale 1
```

`bottom` is the distance in OSD pixels, scale included, from the bottom edge of the window to the top of the row of controls (to the top of the timeline's strip, 24 px at scale 1, when the row is empty). It has the same value whether the controls are shown or hidden, so whatever is placed above it does not move with them. It changes only with the scale or the row (the `controls` option, a button that appears or goes), and it is deleted while suji is turned off.

suji only takes clicks where it draws: on the row and on the timeline's strip, while they are on screen, and on the [action buttons](#action-buttons). Elsewhere above `bottom`, clicks are left to mpv and to other scripts, with one exception: while a menu of suji is open, any menu, a click anywhere in the window is suji's. On the menu it chooses; anywhere else it only closes the menu, and nothing else gets it. Right after a click on a menu or on an action button, suji also keeps the second click of a double click, for mpv's double-click time or until the mouse moves away; on an action button, that second click runs nothing.

## Knowing that suji is there

- When suji starts, it sends `suji-version <version>` to every script, with `script-message`. The scripts mpv loads at start get it, before or after suji; a script loaded later with `load-script`, while a file plays, does not.
- At any time, a message to suji tells: `mp.commandv("script-message-to", "suji", ...)` returns `nil` (and the error `"error running command"`) when no script called `suji` is loaded, and `true` when the message was delivered. mpv logs nothing in that case. suji ignores messages it does not know, without a word in the log, so a probe like `script-message-to suji hello` is harmless.
- `user-data/suji/enabled` is `true` while suji is on and `false` while it is turned off (`enabled=no`); it is deleted when mpv quits. suji sets it as it loads, and mpv plays nothing until every script has loaded, so it is already there on the first `file-loaded`, also for a script loaded before suji.

A message reaching suji does not mean that a menu opened: while suji is turned off, `open-menu` is delivered (`script-message-to` returns `true`) and does nothing. So check the property before sending `open-menu`, and keep a fallback of your own for when it is not `true`, for example mpv's selector (mpv 0.39 or newer): `local input = require "mp.input"` and then `input.select{...}`; `mp.input` is a module to require, not a field of `mp`, so `mp.input.select(...)` would fail:

```lua
if mp.get_property_native("user-data/suji/enabled") == true then
    mp.commandv("script-message-to", "suji", "open-menu", json)
else
    -- no suji, or suji turned off: show the choice some other way
end
```

`user-data/suji/version` (suji 0.3.1 or newer) holds the same text as `suji-version`, for example `"0.3.1"`. suji sets it as it loads, just before `user-data/suji/enabled`, and deletes it when mpv quits; it stays while suji is turned off, because suji is still loaded and still answers messages. So a missing version means no suji, and a version with `enabled` set to `false` means suji turned off. Unlike the message, it is also there for a script loaded later with `load-script`. Read it on `file-loaded` or later, for example when your button is needed, not while your script loads: mpv loads the scripts at the same time, so suji may not have set it yet.

suji 0.3.0 already has `show-action` but not this property, only the message, so keep the message as a fallback. Compare versions by their numbers, not as text: as text, `"0.10"` would come before `"0.9"`. For example, to use `show-action` only with suji 0.3.0 or newer:

```lua
local announced -- from suji-version, for suji 0.3.0
mp.register_script_message("suji-version", function(v) announced = v end)

local function suji_at_least(major, minor, patch)
    local v = mp.get_property_native("user-data/suji/version") or announced
    if type(v) ~= "string" then return false end
    local a, b, c = v:match("^(%d+)%.(%d+)%.(%d+)")
    if not a then return false end
    a, b, c = tonumber(a), tonumber(b), tonumber(c)
    if a ~= major then return a > major end
    if b ~= minor then return b > minor end
    return c >= patch
end

mp.register_event("file-loaded", function()
    if suji_at_least(0, 3, 0) and mp.get_property_native("user-data/suji/enabled") == true then
        -- send show-action to suji
    else
        -- draw a button of your own
    end
end)
```

## Icons

Names for `icon` in menus, in `set-button` and in `command:icon:...` in the `controls` option:

`audio`, `auto_awesome`, `check`, `close`, `fullscreen`, `history`, `info`, `language`, `more`, `mute`, `next`, `palette`, `pause`, `play`, `playlist`, `prev`, `screenshot`, `settings`, `speed`, `star`, `subtitles`, `system_update_alt`, `text_fields`, `volume0`, `volume1`, `volume2`, `windowed`.

They are suji's own drawings, thin lines on a 24 px grid; some names are the ones scripts for uosc already use, the drawings are not.

## Limits

Any script, and any program connected to mpv's IPC, can send these messages, so suji checks everything it gets:

- A JSON text over 1 MiB is not read.
- Broken JSON, JSON that is not an object (a list, a string...), a `type` that is not a string or is too long, `items` that is not a list and an action button without a `text` are ignored with one warning in the mpv console. Other fields of the wrong type are left out silently (see [The menu](#the-menu)).
- An item never carries a function: only `value` runs anything.
- Warnings are limited to 20 every 10 seconds, so a script that sends messages without stopping does not fill the log.
- Scripts are not kept apart from each other: any of them can replace, update or close a menu another one opened, or change its button or action button, by using the same `type`, name or id.

## Examples

A menu that changes while it is open, with `update-menu`:

```lua
local utils = require "mp.utils"
local me = mp.get_script_name()

local function menu()
    local speed = mp.get_property_number("speed", 1)
    local items = {}
    for _, s in ipairs({ 1, 1.5, 2 }) do
        items[#items + 1] = { title = s .. "x", active = math.abs(speed - s) < 0.01,
                              value = { "script-message-to", me, "speed", tostring(s) } }
    end
    return utils.format_json({ type = me .. "-speed", title = "Speed", items = items, keep_open = true })
end

mp.register_script_message("speed", function(s) mp.set_property_number("speed", tonumber(s)) end)
mp.add_key_binding(nil, "open-menu", function()
    mp.commandv("script-message-to", "suji", "open-menu", menu())
end)
-- Only redraws the menu if it is open; does nothing otherwise.
mp.observe_property("speed", "number", function()
    mp.commandv("script-message-to", "suji", "update-menu", menu())
end)
```

With `button:myscript` in `controls`, a button that opens it and shows whether the speed is changed:

```lua
local utils = require "mp.utils"
local me = mp.get_script_name()

local function button()
    local speed = mp.get_property_number("speed", 1)
    -- A badge holds 3 characters: one decimal below 10 (1.25 shows 1.3).
    local rounded = speed < 10 and math.floor(speed * 10 + 0.5) / 10 or math.floor(speed + 0.5)
    mp.commandv("script-message-to", "suji", "set-button", me, utils.format_json({
        icon = "speed",
        command = { "script-binding", me .. "/open-menu" },
        active = speed ~= 1,
        badge = speed ~= 1 and ("%g"):format(rounded) or nil,
    }))
end

mp.observe_property("speed", "number", button)
-- suji may start after this script: then the first set-button found no one.
mp.register_script_message("suji-version", button)
```

The menu comes out of that button, because it opens right after the click.

An action button while the opening plays, with a button of the script's own when suji is not there or is turned off:

```lua
local utils = require "mp.utils"
local me = mp.get_script_name()

local function skip() mp.commandv("seek", "90") end -- to the end of the opening
mp.register_script_message("skip", skip)

local function own_button(on)
    -- The script's own drawing, for when suji is not there or is turned off.
end

-- Called when the opening starts (on = true) and when it ends.
local function skip_button(on)
    local suji = mp.get_property_native("user-data/suji/enabled") == true
    if on and suji then
        mp.commandv("script-message-to", "suji", "show-action", "skip-op", utils.format_json({
            text = "Skip opening ›",
            command = { "script-message-to", me, "skip" },
        }))
    else
        -- Harmless without suji: the message reaches no one.
        mp.commandv("script-message-to", "suji", "hide-action", "skip-op")
    end
    own_button(on and not suji)
end
```

`skip` runs on a click, and suji keeps the button until the script hides it, so once the seek has left the opening behind, the same code that ends the opening calls `skip_button(false)`. A new file removes the button anyway. If suji is turned off while the button is up, it goes, and it does not come back by itself when suji is turned on again. A script can watch `user-data/suji/enabled` for both: draw its own button when it turns `false`, and send `show-action` again when it turns `true`, if the opening is still playing.
