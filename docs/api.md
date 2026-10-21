# suji for script authors

Other mpv scripts can open menus in suji and put their own buttons in its row, with script messages. This page lists what suji understands.

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

suji only takes clicks where it draws: on the row and on the timeline's strip, while they are on screen. Above `bottom`, clicks are left to mpv and to other scripts, with one exception: while a menu of suji is open, any menu, a click anywhere in the window is suji's. On the menu it chooses; anywhere else it only closes the menu, and nothing else gets it. Right after a click on a menu, suji also keeps the second click of a double click, for mpv's double-click time or until the mouse moves away.

## Knowing that suji is there

- When suji starts, it sends `suji-version <version>` to every script, with `script-message`. Only the scripts already running get it.
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

## Icons

Names for `icon` in menus, in `set-button` and in `command:icon:...` in the `controls` option:

`audio`, `auto_awesome`, `check`, `close`, `fullscreen`, `history`, `info`, `language`, `more`, `mute`, `next`, `palette`, `pause`, `play`, `playlist`, `prev`, `screenshot`, `settings`, `speed`, `star`, `subtitles`, `system_update_alt`, `text_fields`, `volume0`, `volume1`, `volume2`, `windowed`.

They are suji's own drawings, thin lines on a 24 px grid; some names are the ones scripts for uosc already use, the drawings are not.

## Limits

Any script, and any program connected to mpv's IPC, can send these messages, so suji checks everything it gets:

- A JSON text over 1 MiB is not read.
- Broken JSON, JSON that is not an object (a list, a string...), a `type` that is not a string or is too long and `items` that is not a list are ignored with one warning in the mpv console. Other fields of the wrong type are left out silently (see [The menu](#the-menu)).
- An item never carries a function: only `value` runs anything.
- Warnings are limited to 20 every 10 seconds, so a script that sends messages without stopping does not fill the log.
- Scripts are not kept apart from each other: any of them can replace, update or close a menu another one opened, or change its button, by using the same `type` or button name.

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
