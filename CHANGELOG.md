# Changelog

All notable changes to this project will be documented in this file.

## [1.1.8] - 2026-07-29

### Fixed
- Generated puzzles had no uniqueness verification at all — measured as
  low as 5 in 15 puzzles actually having a unique solution at some
  size/difficulty combinations. Added a color-aware uniqueness solver
  (generalized from nonogram.koplugin's line-solving technique) and
  reworked generation to verify each puzzle before accepting it. Every
  size and difficulty is now guaranteed unique.
