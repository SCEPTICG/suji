# suji

A minimal on-screen controller for [mpv](https://mpv.io), written from scratch in Lua.

*suji* (筋) is Japanese for "line" or "stripe": while you watch, all you see is a thin progress line along the bottom edge. Move the mouse closer and it grows into a full seek bar with the controls you need, then fades away again.

> **Status:** v0.3.1. It can be installed by hand; there are no packages yet.

## Installation

suji is a folder of Lua scripts. It goes in the `scripts` folder inside mpv's configuration folder, which is:

| System | mpv configuration folder |
| --- | --- |
| Linux and BSD | `~/.config/mpv/` (or `$XDG_CONFIG_HOME/mpv/`) |
| macOS | `~/.config/mpv/` |
| Windows | `%APPDATA%\mpv\` (for example `C:\Users\<name>\AppData\Roaming\mpv\`), or the `portable_config` folder next to `mpv.exe` if there is one |

If `$MPV_HOME` is set, that folder is used instead on every system. Create the folders that do not exist yet.

1. Copy the `suji` folder of this repository into `scripts/`, so that you have `scripts/suji/main.lua`.
2. Optional: copy `docs/suji.conf` to `script-opts/suji.conf` and change the options you want.

There is no need to touch `mpv.conf`: suji turns off mpv's built-in controller (the OSC) by itself.

### One interface at a time

suji turns off mpv's OSC, but it cannot know whether another interface is installed (uosc, ModernZ or any other script that draws controls). If there is one, remove it from `scripts/`, or set `enabled=no` in the options of one of the two.

### Uninstalling

Delete the `scripts/suji` folder (and `script-opts/suji.conf`, if you made one).

## Usage

- **Timeline:** click to seek, or drag. While the cursor is on the timeline, the time in the row shows the time under the cursor, dimmed.
- **Play/pause:** the button on the left.
- **Time:** click it to switch between the duration and the remaining time.
- **Volume:** click the speaker to mute, click or drag the slider to set the volume, and use the wheel over either to change it by 5.
- **Fullscreen:** the button on the right.
- **Menus:** the five buttons before the volume, described below.

The controls appear as the mouse gets close to the bottom of the window and hide when it moves away or stays still for a moment. They stay up while paused, while the cursor is on them and while dragging. Double clicks on the controls do not toggle fullscreen; everywhere else, mpv's mouse bindings work as usual.

Above the controls suji shows the title: mpv's `media-title`, or the file name without its extension when the file has no title. Another script can replace it, see below.

## Menus

Each menu opens upwards from its button. A button with nothing to offer is hidden.

- **Subtitles:** Off, the subtitle tracks and *Load from clipboard* (a path or URL in the clipboard, mpv 0.40 or newer). Shown whenever a file is loaded.
- **Audio:** the audio tracks. Shown when there is more than one.
- **Playlist:** the chapters, then the playlist. The playlist lists video and audio files and URLs, and the file playing; folders and files with no extension are left out. Shown when the file has chapters or the playlist has more than one entry to list.
- **Speed:** the playback speeds from 0.25× to 4×. Away from 1×, the button shows the speed in its corner. Shown whenever a file is loaded.
- **More:** the video track and the editions when there is a choice (a new edition restarts playback), and *Open from clipboard* (mpv 0.40 or newer). Hidden when it has none of them.

Click an entry to choose it; the active one has a thin mark on its left. The wheel scrolls a long list, and the arrow keys and Enter work too. A menu closes after a choice, with a click anywhere outside it (that click does nothing else) or with Esc. While a menu is open the controls stay on screen.

## Options

All options, with their defaults and what they do, are in [`docs/suji.conf`](docs/suji.conf):

| Option | Default | |
| --- | --- | --- |
| `enabled` | `yes` | `no` turns suji off; the OSC comes back only if suji turned it off |
| `idle_line` | `yes` | thin progress line while hidden |
| `accent` | `ffffff` | colour of the progress (rrggbb) |
| `pause_on_drag` | `no` | pause while dragging the timeline |
| `remaining_time` | `no` | show the remaining time at start |
| `hide_delay` | `1.5` | seconds without movement before hiding |
| `proximity` | `120` | distance in px where the bar reacts |
| `scale` | `1` | size, times the system's HiDPI scale |
| `debug` | `no` | log to the mpv console |

`script-opts/suji.conf` is read when mpv starts; changes to the file apply the next time mpv is opened. While mpv runs, options can be changed through the `script-opts` property, with a `suji-` prefix, and suji applies them at once:

```
change-list script-opts append suji-scale=1.5
```

That works from the console, from a key in `input.conf` (`F9 change-list script-opts append suji-enabled=no`) or from another script, and lasts until mpv is closed. On the command line, `--script-opts=suji-scale=1.5` sets an option for that session.

## Customising the controls

The `controls` option chooses which elements the row shows and in which order. The default is the row described above:

```
controls=pause,time,space,subtitles,audio,playlist,speed,more,volume,fullscreen
```

- The elements are `pause`, `time`, `volume`, `fullscreen` and the menus `subtitles`, `audio`, `playlist`, `speed` and `more`.
- `space` pushes what follows it to the right; `gap` leaves a small hole.
- `command:icon:command` adds a button that runs an mpv command, for example `command:x:playlist-next`.
- `button:name` places a button that another script defines (see [For script authors](#for-script-authors)).
- A condition in `<...>` before an element shows it only when it holds, for example `<has_playlist>command:x:playlist-next`. A hidden element leaves no gap.

The timeline and the title are always there. All the elements, conditions and limits are explained in [`docs/suji.conf`](docs/suji.conf). The option can be changed while mpv runs, and the row changes at once; use `append` so the commas stay in the value:

```
change-list script-opts append suji-controls=pause,space,fullscreen
```

On the command line, the same goes for `--script-opts-append=suji-controls=pause,space,fullscreen`.

## For other scripts: the title

```
script-message-to suji set-title "<series>" "<episode>"
```

- With both, suji shows a two-line title: the series in smaller capital letters above the episode.
- With only one of them (the other empty or missing), a one-line title.
- With both empty, suji goes back to `media-title`.
- The title is cleared when the file changes, so send it again for each file.
- Each part is cut to 200 characters.

The name and arguments of this message are meant to stay as they are, so scripts can rely on them.

## For script authors

Other scripts can open menus in suji (`open-menu`, `update-menu`, `close-menu`), put their own buttons in the row (`set-button` and `button:name` in `controls`), see which menu is open (`user-data/suji/menu/type`), know how high the controls reach (`user-data/suji/margins`) and tell that suji is loaded. The messages, the JSON of a menu, the icon names and two examples are in [`docs/api.md`](docs/api.md). That API is at 0.x and may still change.

## Requirements

mpv 0.39 or newer.

## Tests

`tests/run.sh` runs the unit tests with Lua 5.1 (`LUA=luajit tests/run.sh` for another Lua), a smoke test with a windowless mpv and, if `xvfb-run` is installed, tests with real clicks and messages in a virtual display.

## License

suji is licensed under the [GNU Lesser General Public License v2.1](LICENSE) or (at your option) any later version. It is written from scratch and does not include code from other mpv interfaces.
