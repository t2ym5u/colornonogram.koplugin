# colornonogram.koplugin

A Colour Nonogram (Colour Picross) puzzle plugin for [KOReader](https://github.com/koreader/koreader).

## Screenshot

![Screenshot](images/colornonogram.png)

## Rules

Like a Nonogram but cells are filled with colours. Each clue gives a colour and a run length. Different colours may be directly adjacent; same-colour runs must have at least one empty cell between them. Solve by deducing which colour (if any) belongs in each cell.

## Features

- **Two grid sizes** — 6×6 and 8×8
- **Three difficulty levels, no guessing** — every puzzle is solved by line
  logic alone (each row or column, from its clue and the cells already
  known), which also proves its solution unique. The levels differ by how
  long that chain of deductions is: *Easy* grids are full and settle in two
  or three sweeps, *Medium* takes four or five, *Hard* grids are emptier
  and take six or more.
- **Four display modes** — choose in the menu → **Display**:
  - *Original*: different shades of grey, for greyscale e-ink
  - *Patterns*: solid black, stripes and dots, for greyscale e-ink
  - *Red, green, blue*: for colour e-ink
  - *Blue, orange, purple*: for colour e-ink, easier to tell apart with red-green colour blindness

  Until you choose, colour e-readers with KOReader's colour rendering on start with *Red, green, blue*, and others with *Original*.
- **Check** — highlights incorrect colours and empty marks; untouched cells are ignored
- **Hint** — two taps: the first says which cell is about to give, the second acts on it. A cell that contradicts the solution is always reported before a fresh one is revealed
- **Auto-save** — puzzle state saved and restored on next launch

## Installation

1. Download `colornonogram.koplugin.zip` from the [latest release](../../releases/latest).
2. Extract into the `plugins/` folder of your KOReader data directory.
3. Restart KOReader.
4. Open the menu → **Tools** → **Colour Nonogram**.

## Controls

| Action | How |
|--------|-----|
| Choose a colour or the empty mark (X) | Tap it in the palette below the board |
| Apply it to a cell | Tap cell |
| Clear a cell | Tap it again with the same colour or mark |
| Check progress | Tap **Check** |
| New puzzle | Tap **New game** |
| Show rules | Tap **Rules** |

## License

GPL-3.0 — see [LICENSE](LICENSE).
