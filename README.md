# colornonogram.koplugin

A Colour Nonogram (Colour Picross) puzzle plugin for [KOReader](https://github.com/koreader/koreader).

## Screenshot

*(Screenshot to be added.)*

## Rules

Like a Nonogram but cells are filled with colours. Each clue gives a colour and a run length. Different colours may be directly adjacent; same-colour runs must have at least one empty cell between them. Solve by deducing which colour (if any) belongs in each cell.

## Features

- **Multiple grid sizes**
- **Colour palette** — rendered as distinct patterns on greyscale e-ink
- **Cross mark** — mark cells known to be empty
- **Check** — highlights incorrect cells
- **Auto-save** — puzzle state saved and restored on next launch

## Installation

1. Download `colornonogram.koplugin.zip` from the [latest release](../../releases/latest).
2. Extract into the `plugins/` folder of your KOReader data directory.
3. Restart KOReader.
4. Open the menu → **Tools** → **Colour Nonogram**.

## Controls

| Action | How |
|--------|-----|
| Cycle cell colour | Tap cell |
| Mark as empty | Long-press or right-tap |
| Check progress | Tap **Check** |
| New puzzle | Tap **New** |
| Show rules | Tap **Rules** |

## License

GPL-3.0 — see [LICENSE](LICENSE).
