# Changelog

All notable changes to this project will be documented in this file.

## [1.6.0] - 2026-11-06

### Changed
- No puzzle needs guessing any more, and the levels are in order. A puzzle
  used to be accepted when a branching search found it had one solution,
  so some could only be finished by trial and error (about 1 in 40 on 8×8),
  and if 400 draws found none, a grid with several solutions was kept.
  Now a puzzle is kept only if line logic alone finishes it (each row or
  column, from its clue and the cells already known).
- Difficulty is now how long that chain of deductions is, counted in
  sweeps (all rows, or all columns). Easy used to be the emptiest grid,
  which is the hardest to reason out, and Hard the fullest. Measured over
  40 puzzles per size: Easy 2.8 / 3.0 sweeps on 6×6 / 8×8 (before 4.2 /
  5.8), Medium 4.3 / 4.5 (before 3.9 / 4.9), Hard 6.4 / 7.1 (before 3.3 /
  4.4).
- A progress bar shows if a puzzle takes a moment to build (Hard is under
  0.02 s on a desktop, about 0.5 s on a Kobo).
- The same seed gives a different puzzle than in 1.5.2, so the Daily
  Challenge puzzle changes once.

### Fixed
- The puzzle counts as solved as soon as the grid keeps every clue, even
  if it differs from the stored answer (a game saved with an older version
  may have more than one).

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
- New game and opening the game each build one puzzle instead of two: the
  board used to generate a puzzle on creation that the screen then replaced
  (or that a saved game overwrote), so opening a saved game no longer
  waits for a puzzle at all. Today's Daily Challenge grid is a different one
  than with 1.4.3.

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
- Redesigned play screen: the board, clues included, fills the room the
  controls leave, with one edge around it and a full-width
  Check/Hint/Clear/Undo bar.
- Reveal moved from the action bar to the title-bar menu as "Show solution",
  after the size and "Difficulty: Medium" (was "Diff: Medium") entries.
- The status line reads "10×10 · Medium · Filled: 20/60" and wraps in
  landscape instead of being cut off.
- Once the picture is complete (or shown), the action bar shows "New game" in
  place of its buttons.

### Fixed
- The board overflowed the screen on clue-heavy puzzles: the grid was sized on
  its own and the clue strips were added on top. Clues and grid now share one
  cell size that fits.
- Clue numbers overflowed their slots on high-DPI screens; they are now fitted
  to them. The closing grid lines no longer spill past the board's edge.
- The rules promised a long-press to mark a cell empty, which the game never
  did; they now say a tap cycles the colours and back to empty.
- An applied Hint no longer wipes the saved game (game-common saved it as
  nil). When a hint fills the last cell, the status now shows the win message.

## [1.2.2] - 2026-10-07

### Fixed
- The Tools menu entry is translated again. `main.lua` took `_` from
  KOReader's `gettext`, which knows nothing of this plugin's strings, so the
  menu label stayed English while the game's own screen, which goes through
  `i18n`, was translated. `_` now comes from `i18n` here too.


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
- Generated puzzles had no uniqueness verification at all — measured as
  low as 5 in 15 puzzles actually having a unique solution at some
  size/difficulty combinations. Added a color-aware uniqueness solver
  (generalized from nonogram.koplugin's line-solving technique) and
  reworked generation to verify each puzzle before accepting it. Every
  size and difficulty is now guaranteed unique.
