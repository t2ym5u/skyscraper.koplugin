# Changelog

All notable changes to this project will be documented in this file.

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
