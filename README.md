# suji

A minimal on-screen controller for [mpv](https://mpv.io), written from scratch in Lua.

*suji* (筋) is Japanese for "line" or "stripe": while you watch, all you see is a thin progress line along the bottom edge. Move the mouse closer and it grows into a full seek bar with the controls you need, then fades away again.

> **Status:** early development. Nothing to install yet.

## Planned for v0.1

- A 2 px progress line at rest (can be turned off), growing into a full-width seek bar as the mouse gets close
- Time under the cursor, chapter marks, buffered range
- Play/pause, time, volume and fullscreen
- Title (or series and episode, if another script provides them)
- No backgrounds: shadows keep it readable on bright and dark scenes
- Idle cost of zero: nothing redraws while nothing changes

Requires mpv 0.39 or newer.

## License

suji is licensed under the [GNU Lesser General Public License v2.1](LICENSE) or (at your option) any later version. It is written from scratch and does not include code from other mpv interfaces.
