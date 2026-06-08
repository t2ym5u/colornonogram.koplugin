# Color Nonogram

> **Status: stub — not yet implemented**

## Description

Nonogram / Picross variant where cells can be filled with multiple colours. Clues specify consecutive runs of each colour.

## Files to create

- `board.lua` — game logic, puzzle generator, serialize/load
- `board_widget.lua` — grid rendering and tap gestures
- `screen.lua` — full-screen layout (buttons + board)
- `main.lua` — PluginBase entry point

## Notes

Grid-based logic puzzle — use GridWidgetBase from game-common.
