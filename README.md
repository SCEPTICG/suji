# suji

A minimal on-screen controller for [mpv](https://mpv.io), written from scratch in Lua.

*suji* (筋) is Japanese for "line" or "stripe": while you watch, all you see is a thin progress line along the bottom edge. Move the mouse closer and it grows into a full seek bar with the controls you need, then fades away again.

> **Status:** v0.6.1. It installs with one line (see [Installation](#installation)) or by hand; there are no packages yet.

## Installation

If you use [hikari](https://github.com/SCEPTICG/hikari-mpv), install suji with the hikari installer (`-Interface suji`) instead: it knows how to put suji in without breaking hikari. The suji installer leaves any folder with hikari in it untouched.

On **Windows**, open PowerShell and run:

```
irm https://github.com/SCEPTICG/suji/releases/latest/download/suji.ps1 | iex
```

On **macOS and Linux**, open a terminal and run:

```
curl -fsSL https://github.com/SCEPTICG/suji/releases/latest/download/suji.sh | bash
```

The installer asks whether to install (or update) or uninstall, then lists the players it finds with their configuration folders (mpv, mpv.net and AnimeJaNai on Windows; mpv from Homebrew or mpv.app on macOS; mpv from a package on Linux) and works on the ones you choose. Its messages are in Spanish when the system is, in English otherwise. It needs no administrator rights and refuses to run with them (or with `sudo`). Run the same line again to update.

mpv from **Flatpak or Snap** is not supported by the installer: it leaves those folders alone. Install suji there [by hand](#by-hand).

When it installs or updates suji in a folder, it:

1. Backs up the files it is about to change, next to the folder (`mpv-respaldo-suji-<date>`, for example). It keeps the three newest backups.
2. Downloads the `suji.zip` of the same release and [thumbfast](https://github.com/po5/thumbfast) (a fixed version), and checks the SHA256 of each before using it. A thumbfast that is already that exact file is not downloaded again.
3. Moves other interfaces that draw their own controls (uosc, ModernZ, the `osc.lua` of mpv and similar) to `scripts-apartados-suji`, after asking. Nothing is deleted, and they go back when you uninstall.
4. Copies `scripts/suji` and `scripts/thumbfast.lua`.
5. Adds a marked block with `osc=no` at the start of `mpv.conf` and leaves the rest of the file as it was.
6. Writes `script-opts/thumbfast.conf` when there is none (network streams, decoding on the GPU, thumbnails up to 200×200). If there is one, it only adds `mpv_path` when the player needs it (mpv on macOS, mpv.net and AnimeJaNai). It never touches `suji.conf`.

What it did is noted in `suji-installed.txt`, in the same folder, so it can be undone.

### Uninstalling

Run the installer again and choose *Uninstall*, or go straight to it:

```
& ([scriptblock]::Create((irm https://github.com/SCEPTICG/suji/releases/latest/download/suji.ps1))) -Action uninstall
```

```
curl -fsSL https://github.com/SCEPTICG/suji/releases/latest/download/suji.sh | bash -s -- --action uninstall
```

It backs up again, removes `scripts/suji` and the block in `mpv.conf`, and asks whether to remove thumbfast too, whether to delete your settings (`script-opts/suji.conf` and `suji-size`) and whether to move back the interfaces it set aside.

Options for scripts, the same on every system: `-Action install|uninstall` (`--action`), `-Target <folder>` (`--target`, to work on that folder instead of choosing) and `-Yes` (`--yes`, no questions: the default answer to everything; it needs `-Action`, and `-Target` when more than one folder can be chosen: folders with hikari, and on Linux Flatpak and Snap ones, do not count). In a terminal the questions are menus you answer with the arrow keys, Space and Enter; `-NoMenu` (`--no-menu`) asks with numbers instead. On macOS and Linux they go after `bash -s --`, as above. Exit codes: 0 done or cancelled, 1 a folder failed, 2 wrong usage or nothing to do.

### Checking the installer first

Both lines run whatever the server sends without checking it: the installer verifies everything it downloads, but it cannot verify itself. The addresses always point to files attached to a tagged release, never to the `main` branch. To check it yourself, download the installer and `SHA256SUMS` from the [release page](https://github.com/SCEPTICG/suji/releases/latest), compare the hash and run the file:

```
Get-FileHash .\suji.ps1 -Algorithm SHA256
Get-Content .\SHA256SUMS
powershell -ExecutionPolicy Bypass -File .\suji.ps1
```

```
shasum -a 256 suji.sh        # sha256sum suji.sh on Linux
cat SHA256SUMS
bash suji.sh
```

The hash must be the one `SHA256SUMS` lists for that file. Each release's installer only installs the `suji.zip` of that same release, and only if its SHA256 matches the one written inside it. `SHA256SUMS` comes from the same release as the installer, so this catches a file that was damaged or changed on the way to you, but not a compromised account; reading the installer before running it is the only check that does not depend on the account.

### By hand

suji is a folder of Lua scripts. It goes in the `scripts` folder inside mpv's configuration folder, which is:

| System | mpv configuration folder |
| --- | --- |
| Linux and BSD | `~/.config/mpv/` (or `$XDG_CONFIG_HOME/mpv/`) |
| Linux, mpv from Flatpak | `~/.var/app/io.mpv.Mpv/config/mpv/` |
| Linux, mpv from Snap | `~/snap/mpv/current/.config/mpv/` |
| macOS | `~/.config/mpv/` |
| Windows | `%APPDATA%\mpv\` (for example `C:\Users\<name>\AppData\Roaming\mpv\`), or the `portable_config` folder next to `mpv.exe` if there is one |

If `$MPV_HOME` is set, that folder is used instead on every system. Create the folders that do not exist yet.

1. Copy the `suji` folder of this repository into `scripts/`, so that you have `scripts/suji/main.lua`.
2. Optional: copy `docs/suji.conf` to `script-opts/suji.conf` and change the options you want.

There is no need to touch `mpv.conf`: suji turns off mpv's built-in controller (the OSC) by itself.

suji turns off mpv's OSC, but it cannot know whether another interface is installed (uosc, ModernZ or any other script that draws controls). If there is one, remove it from `scripts/`, or set `enabled=no` in the options of one of the two.

To uninstall by hand, delete the `scripts/suji` folder (and `script-opts/suji.conf`, if you made one, and `suji-size` in mpv's state or configuration folder, if you chose a size: see [Size](#size)).

## Usage

- **Timeline:** it rises from the bottom edge to just above the row as the controls come. Click to seek, or drag; the part already loaded is a lighter grey. While the cursor is on the timeline, the time in the row shows the time under the cursor, dimmed; with [thumbnails](#thumbnails), that time goes in the thumbnail's box instead.
- **Play/pause:** the button on the left.
- **Previous and next:** after it, the previous and the next entry of the playlist, files or streams. They are only there when the playlist has more than one entry; the previous one hides on the first entry and the next one on the last.
- **Volume:** on the left, only the speaker at first. With the cursor on it, the slider unfolds and pushes the time to the right; it folds again a moment after the cursor leaves both. Click the speaker to mute, click or drag the slider to set the volume, and use the wheel over either to change it by 5.
- **Time:** click it to switch between the duration and the remaining time.
- **Fullscreen:** the button on the right.
- **Menus:** the five buttons before fullscreen, described below.

The controls appear as the mouse gets close to the bottom of the window and hide when it moves away or stays still for a moment. They stay up while paused, while the cursor is on them and while dragging. Double clicks on the controls do not toggle fullscreen; everywhere else, mpv's mouse bindings work as usual.

At the top left suji shows the title, with the controls: mpv's `media-title`, or the file name without its extension when the file has no title. Another script can replace it, see below.

## Menus

Each menu opens upwards above the timeline, in line with its button. A button with nothing to offer is hidden.

- **Subtitles:** Off, the subtitle tracks and *Load from clipboard* (a path or URL in the clipboard, mpv 0.40 or newer). Shown whenever a file is loaded.
- **Audio:** the audio tracks. Shown when there is more than one.
- **Playlist:** the chapters, then the playlist. The playlist lists video and audio files and URLs, and the file playing; folders and files with no extension are left out. Shown when the file has chapters or the playlist has more than one entry to list.
- **Speed:** the playback speeds from 0.25× to 4×. Away from 1×, the button shows the speed in its corner. Shown whenever a file is loaded.
- **More:** the video track and the editions when there is a choice (a new edition restarts playback), *Open from clipboard* (mpv 0.40 or newer) and *Size*. Shown whenever a file is loaded.

Click an entry to choose it; the active one has a thin mark on its left. The wheel scrolls a long list, and the arrow keys and Enter work too. A menu closes after a choice, with a click anywhere outside it (that click does nothing else) or with Esc. While a menu is open the controls stay on screen.

### Size

*Size* in the More menu lists 75%, 90%, 100%, 110%, 125% and 150%. A choice resizes all of suji at once (the row, the timeline, the title, the menus and the action buttons) and the menu stays open, so another size can be tried; Esc or a click outside closes it. 100% is the size the `scale` option gives, and the size chosen multiplies it: with `scale=1.2` and 125%, the factor is 1.5 (still within 0.25 to 8), times the system's HiDPI scale.

suji remembers the size on each computer, in a file of its own, `suji-size`. It holds the percentage and nothing else, and it is written only when a size is chosen. `suji.conf` is never touched. The file goes in mpv's state folder when it exists (mpv creates it the first time it saves something there, such as watch later), else in mpv's configuration folder (see [Installation](#installation)); suji reads the one in the state folder first.

| System | mpv state folder |
| --- | --- |
| Linux and BSD | `~/.local/state/mpv/` (or `$XDG_STATE_HOME/mpv/`) |
| macOS | `~/.config/mpv/`, the configuration folder itself |
| Windows | `%LOCALAPPDATA%\mpv\`, or the `portable_config` folder next to `mpv.exe` if there is one |

A file that cannot be read or holds anything else gives 100%. If the file cannot be written, suji says so once in the mpv console and the size lasts until mpv is closed. With `--no-config` mpv has neither folder, and the size is not remembered.

## Thumbnails

With [thumbfast](https://github.com/po5/thumbfast) installed, suji shows thumbnails on the timeline. thumbfast is a separate script that makes them: put `thumbfast.lua` in the `scripts` folder, as its page explains. suji makes no thumbnails of its own.

While the cursor is on the timeline, or dragging it, a box comes up just above the bar, centred on the cursor: the frame at that time and, under it, the time and the chapter of that moment if the file has chapters (cut if it does not fit). At both ends of the bar the box stays inside the window. While it is there, the row's time shows the position again. The box goes when the cursor leaves the timeline, when the controls hide, when the file changes, when a menu opens and when suji is turned off.

suji asks thumbfast for the frame and where to put it, and draws the box and the line under it; thumbfast draws the image. Everything else is up to thumbfast and its own options, in `script-opts/thumbfast.conf`: the size of the image (it already includes the system's HiDPI scale: suji's `scale` and *Size* grow the box around it, not the image), and whether it works on network files or audio files (both off by default). For mpv.net and other frontends, see thumbfast's page.

suji learns that thumbfast is there, and the size of its images, from the `thumbfast-info` message that thumbfast sends to the other scripts. Until one has arrived, suji acts as if thumbfast were not installed; after that, it keeps the last one.

Without thumbfast, when thumbfast cannot make thumbnails for the file, or with `thumbnails=no`, there is no box and no warning, and the row shows the time under the cursor as before. With `thumbnails=no` suji sends thumbfast nothing.

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
| `scale` | `1` | size, times the system's HiDPI scale and the size chosen in More |
| `thumbnails` | `yes` | thumbnails on the timeline, made by thumbfast (see [Thumbnails](#thumbnails)) |
| `debug` | `no` | log to the mpv console |

`script-opts/suji.conf` is read when mpv starts; changes to the file apply the next time mpv is opened. While mpv runs, options can be changed through the `script-opts` property, with a `suji-` prefix, and suji applies them at once:

```
change-list script-opts append suji-scale=1.5
```

That works from the console, from a key in `input.conf` (`F9 change-list script-opts append suji-enabled=no`) or from another script, and lasts until mpv is closed. On the command line, `--script-opts=suji-scale=1.5` sets an option for that session.

## Customising the controls

The `controls` option chooses which elements the row shows and in which order. The default is the row described above:

```
controls=pause,prev,next,volume,time,space,subtitles,audio,playlist,speed,more,fullscreen
```

If you already have your own `controls=` in `suji.conf`, it stays as it is: only the default changed in 0.7.0.

- The elements are `pause`, `prev`, `next`, `time`, `volume`, `fullscreen` and the menus `subtitles`, `audio`, `playlist`, `speed` and `more`.
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
script-message-to suji set-title "<series>" "<episode>" ["<name>"]
```

- With both, suji shows a two-line title: the series in small grey capital letters above the episode, larger and in bold.
- The name of the episode is optional: it goes after the episode, on the same line, in grey ("Episode 2  The name"). It is only shown with an episode, and with two arguments everything is as before.
- With only one of them (the other empty or missing), a one-line title.
- With both empty, suji goes back to `media-title`.
- The title is cleared when the file changes, so send it again for each file.
- Each part is cut to 200 characters.
- The title shows and hides with the controls: at rest, nothing is left at the top of the window.

The name and arguments of this message are meant to stay as they are, so scripts can rely on them.

## For script authors

Other scripts can open menus in suji (`open-menu`, `update-menu`, `close-menu`), put their own buttons in the row (`set-button` and `button:name` in `controls`), see which menu is open (`user-data/suji/menu/type`), know how high the controls reach (`user-data/suji/margins`) and tell that suji is loaded. The messages, the JSON of a menu, the icon names and two examples are in [`docs/api.md`](docs/api.md). That API is at 0.x and may still change.

## Requirements

mpv 0.39 or newer.

## Tests

`tests/run.sh` runs the unit tests with Lua 5.1 (`LUA=luajit tests/run.sh` for another Lua), a smoke test with a windowless mpv and, if `xvfb-run` is installed, tests with real clicks and messages in a virtual display.

## License

suji is licensed under the [GNU Lesser General Public License v2.1](LICENSE) or (at your option) any later version. It is written from scratch and does not include code from other mpv interfaces.
