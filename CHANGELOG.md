# Changelog

All notable changes to this project will be documented in this file.

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
