# GagaFX MQL5 Scripts Package

This repo is a clean, minimal package structure to organize your MetaTrader 5 scripts. Drop your `.mq5` files under `MQL5/Scripts/` and use the deploy helper to copy/symlink them into your MetaTrader 5 Data Folder.

## Layout

- `MQL5/Experts/` — Expert Advisors (`.mq5` with OnTick/OnInit)
- `MQL5/Scripts/` — one‑off scripts (no OnTick)
- `MQL5/Include/` — shared headers (`.mqh`) for reuse across scripts
- `MQL5/Libraries/` — compiled libs and third-party code (optional)
- `MQL5/Files/` — runtime files output/input used by scripts
- `tools/` — helper scripts for deployment

## .editorconfig

Basic formatting defaults are provided (`4` spaces, LF endings). Adjust as needed for your editor and style.

## Adding your script

1. Place EAs in `MQL5/Experts/YourEA.mq5` (like `Experts/GagaFX.mq5`). Place single‑run scripts in `MQL5/Scripts/`.
2. Optionally add shared headers in `MQL5/Include/*.mqh` and `#include <YourHeader.mqh>`.

## Deploying to MetaTrader 5

The most reliable way to find your MT5 Data Folder is inside MetaTrader:

- In MetaTrader 5: File → Open Data Folder → this opens the root (contains `MQL5/`).

Then you have two options:

- Copy: run `bash tools/deploy.sh --data-dir "/path/to/Data Folder"` to copy this repo's `MQL5` contents into the terminal's `MQL5` directory.
- Symlink: see instructions in `tools/deploy.sh --help` to symlink `MQL5/Scripts` to your terminal's `MQL5/Scripts` so edits here appear instantly in MetaEditor.

Notes:
- Always keep file names stable to preserve compiled `.ex5` cache in MetaTrader.
- If you use symlinks on Windows, run Git Bash or WSL with admin rights when creating them.

## MetaEditor / Compilation

You don't need to compile here. Open MetaEditor (from MetaTrader) and compile your script there. This repo just tracks your source and structure.

## License

No license set. Add one if you plan to share publicly.
