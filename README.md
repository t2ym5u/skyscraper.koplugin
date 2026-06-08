# Skyscraper

> **Status: stub — not yet implemented**

## Description

Place 1–N in each row and column (Latin square). Outside clues count how many 'buildings' are visible from that direction.

## Files to create

- `board.lua` — game logic, puzzle generator, serialize/load
- `board_widget.lua` — grid rendering and tap gestures
- `screen.lua` — full-screen layout (buttons + board)
- `main.lua` — PluginBase entry point

## Notes

Number placement puzzle — use GridWidgetBase from game-common.
