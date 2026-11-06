# Changelog

All notable changes to this project will be documented in this file.

## [1.6.0] - 2026-11-05

### Changed
- Every puzzle can now be solved by logic alone, with no guessing. A clue
  is only hidden if the grid can still be filled step by step: what a 1 or
  an N clue says, how tall a cell close to a clue can be, a cell with one
  height left, the one place left for a height in a row or column, a row
  with only two empty cells, and the orderings a row or column allows with
  its clues. Before, a good share of puzzles (about 3 in 10 on 5×5 Medium
  and Hard, and some Easy ones) had a single solution that could only be
  found by trial and error.
- The three levels are really different now. Easy needs only the simple
  steps and shows a few more clues on 4×4. Medium needs to work through
  the orderings of a row or column. Hard shows fewer clues than Medium and
  needs that step more often.
- A puzzle is won as soon as the grid keeps the rules: every row and column
  holds each height once and every clue sees the right count.
- Puzzles are built faster: at most about 0.03 s on a desktop (5×5 Hard
  could take 0.5 s), with a progress bar if it ever takes a while on the
  e-reader.
- The Daily Challenge grid for the day of the update changes once.
  Games in progress are kept.

## [1.5.2] - 2026-11-04

### Fixed
- A game no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.5.1] - 2026-11-04

### Changed
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.

## [1.5.0] - 2026-11-04

### Changed
- Much faster puzzle generation: the uniqueness check now places a whole
  row at a time and drops orderings that contradict a clue right away,
  instead of filling cells one by one and checking clues only once a row or
  column is complete. 5×5 Hard went from up to 6 s on a desktop (minutes on
  a Kobo) to a few hundredths of a second; puzzles are unchanged (still
  exactly one solution).
- Opening the game no longer builds a puzzle it then throws away (it was
  generated even when a saved game was about to be restored), and New game
  builds one puzzle instead of two.

## [1.4.3] - 2026-11-03

### Changed
- Picks up game-common 1.11.0: the shared on-screen keyboard (where used)
  gives every key the same letter size, and the no-repeat history helper.

## [1.4.2] - 2026-11-02

### Changed
- Picks up game-common 1.10.0: the shared Tools → Games menu also lists
  the games' new "· multiplayer" entries under Party & quiz.

## [1.4.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.4.0] - 2026-10-30

### Added
- "Daily Challenge" in the menu, right after "New game": today's puzzle at
  your size and difficulty, the same grid for everyone playing it today.
  Needs game-common 1.7.0.

## [1.3.0] - 2026-10-30

### Changed
- Redesigned play screen: the board is larger, filling the room the controls
  leave, with one even digit pad and a full-width action bar under the status
  line. The grid's thick outer border is now the board's only frame.
- The status line reads "5×5 · Medium · Empty: 12" and wraps in landscape
  instead of being cut off.
- The title-bar menu shows "Size: …" and "Difficulty: …" (was "Grid: …" and
  "Diff: …"), like every other game.
- Once the puzzle is solved, the action bar shows "New game" in place of
  Erase/Check/Hint, so the next round no longer needs the menu.

### Fixed
- The clues around the grid came out nearly twice too big on high-DPI
  readers, and digits overflowed their cells (the shared font fit accepted
  every size). Both now fit on every screen.
- The grid's right and bottom border lines were drawn past its edge.
- Using a hint wiped the saved game; it is now kept. When a hint fills the
  last cell, the status shows the win message.

## [1.2.2] - 2026-10-07

### Fixed
- The Tools menu entry is translated again. `main.lua` took `_` from
  KOReader's `gettext`, which knows nothing of this plugin's strings, so the
  menu label stayed English while the game's own screen, which goes through
  `i18n`, was translated. `_` now comes from `i18n` here too.
- `i18n_fr.lua` shipped to the device but was never loaded: nothing called
  `i18n.extend()` on it, so the whole table was dead weight. main.lua now
  merges it in before the menu entry is built.


## [1.2.1] - 2026-10-01

### Fixed
- Picks up game-common v1.5.0. Play statistics were recorded under a key no
  tool could match: `ReaderUI`/`FileManager:registerModule()` rewrite a plugin
  instance's `name` to `reader<id>` / `filemanager<id>` right after it is
  built, so this game's sessions were split across two rows and neither
  carried its plugin id. Rows written under the old keys are merged back on
  first read. The same release brings the `stopPlugin()` /
  `deletePluginSettings()` hooks KOReader 2026.07 calls when a plugin is
  deleted from the device (PR #15240).

  No change to this plugin's own code -- it inherits all of it from the
  shared library.

## [1.2.0] - 2026-09-30

### Added
- **Hint** button. Two taps, not one: the first says which cell is about to
  give, the second acts on it -- a player who is told where to look usually
  finds the rest themselves, and only pays for the full reveal if they want
  it. A cell that contradicts the solution is always reported before a fresh
  one is revealed, and on a mistake the hint empties the cell rather than
  solving it.

## [1.1.8] - 2026-07-29

### Fixed
- Generated puzzles had no uniqueness verification at all — a random
  Latin square's full visibility-clue set can itself be ambiguous
  before any clues are even hidden, and the old digging step never
  checked whether the kept clues still forced a single solution. Added
  a backtracking uniqueness solver used both to regenerate the Latin
  square until its full clue set is provably unique and to verify each
  clue removal during digging. Every size and difficulty is now
  guaranteed unique.
