# mpv configuration — Oleks Edition

A Windows-focused mpv config based on [tuilakhanh/mpv-conf](https://github.com/tuilakhanh/mpv-conf),
with a right-click wheel menu, Explorer-matching playlist order and a safer delete.

![thumb](https://github.com/tuilakhanh/mpv-conf/assets/17153084/908b4514-d85f-4c99-b9c1-28245795ea94)

## Install

Put the contents of this repository in a folder named `portable_config` next to `mpv.exe`
(or in `%APPDATA%\mpv`). Tested with a portable mpv build on Windows 10.

## What this edition adds

**Right-click wheel menu** (`scripts/radial-menu.lua`)
- Hold right-click and point; folders fan out as a new ring beyond the slice, no click needed.
  The rings you came through stay visible, with your path highlighted.
- Release on an entry to run it. A quick right-click keeps the wheel open for clicking.
- Options that are on (toggles, loaded shaders, the chosen sort order) show in amber with a dot.
- Built from the `Folder > Item` menu entries in `input.conf`, the same ones the uosc menu uses.
- `Ctrl+right-click` opens the uosc list menu, which has search.

**Keyboard shortcuts screen** — press `?` (or *Tools › Keyboard Shortcuts*) for every key on one screen.

**Playlist order that matches Explorer** (`scripts/sort-playlist.lua`)
- *Match Explorer* (default): sorts by the same column and direction as the Explorer window
  showing the folder (name, date modified, date created, size or type).
- Name sorting reproduces Windows' own comparison: `Ep 2` before `Ep 10`, punctuation before digits.
- Also Name A–Z / Z–A and Newest / Oldest first. The choice is remembered.
- *Include Subfolders* toggle; off by default, remembered in `script-opts/autoload.conf`.
- Available in the wheel (*Sort*), the button next to the playlist controls, and `Alt+P`.

**Safer delete** (`scripts/trash-file.lua`)
- `Del` → Recycle Bin, `Shift+Del` → permanent; both confirm with `Enter`, cancel with `Esc`.
- Playback pauses while the dialog is open and resumes afterwards if it was playing.
- `Ctrl+Z` restores the last trashed files (up to 5).

**Other changes**
- `Up` / `Down` go to the previous / next file. Hold to keep skipping: it starts at about
  8 files a second and speeds up to 40. At the top or end they stop, or wrap round with
  *Sort › Wrap Up/Down*. A press made while a new folder is still being sorted waits for it.
- Resuming a file restores position, tracks and volume, but never zoom or pan.
- Only one folder scanner (`autoload.lua`); uosc's own autoload is off.
- `ytsub` works when mpv is started from Explorer (it used to require `%HOME%`).
- The uosc subtitle download tool (`ziggy`) is not included, as antivirus software flags it.

## Scripts and shaders credits

Scripts
- [mpv-player/autocrop](https://github.com/mpv-player/mpv/blob/master/TOOLS/lua/autocrop.lua),
  [autodeint](https://github.com/mpv-player/mpv/blob/master/TOOLS/lua/autodeint.lua),
  [autoload](https://github.com/mpv-player/mpv/blob/master/TOOLS/lua/autoload.lua) (adds a rescan message)
- [ObserverOfTime/clipshot](https://github.com/ObserverOfTime/mpv-scripts/blob/master/clipshot.lua)
- [po5/evafast](https://github.com/po5/evafast)
- [po5/memo](https://github.com/po5/memo)
- [natural-harmonia-gropius/input-event](https://github.com/natural-harmonia-gropius/input-event)
- [voz.vn/protocol_hook](https://github.com/FirefoxUniverse/FirefoxTweaksVN/tree/main/mpv)
- [natural-harmonia-gropius/quality-menu](https://github.com/natural-harmonia-gropius/mpv-quality-menu)
- [4e6/mpv-reload](https://github.com/4e6/mpv-reload)
- [snylonue/slicing_copy](https://github.com/snylonue/mpv_slicing_copy) (modified)
- [jouni/mpv_sponsorblock_minimal](https://codeberg.org/jouni/mpv_sponsorblock_minimal)
- [Sagnac/streamsave](https://github.com/Sagnac/streamsave)
- [po5/thumbfast](https://github.com/po5/thumbfast)
- [tomasklaen/uosc](https://github.com/tomasklaen/uosc) (5.10)
- [serenae-fansubs/webm](https://github.com/serenae-fansubs/mpv-webm)
- [Idlusen/mpv-ytsub](https://github.com/Idlusen/mpv-ytsub) (modified)
- Oleks Edition: `radial-menu`, `sort-playlist`, `trash-file`, `playlist_repeat`, `mpv-path-helper`

Shaders
- [bjin/mpv-prescalers](https://github.com/bjin/mpv-prescalers) — RAVU, NNEDI3 (LGPL)
- [igv/gist](https://gist.github.com/igv) — FSRCNNX (F8, F16), KrigBilateral / krigbl,
  SSimSuperRes, SSimDownscaler (Shiandow)
- [bloc97/Anime4K](https://github.com/bloc97/Anime4K) — A4K Restore, Clamp Highlights (MIT)
- [Artoriuz/ArtCNN](https://github.com/Artoriuz/ArtCNN) — ArtCNN; Ani4Kv2 and AniSD models
  trained by Sirosky (CC BY-NC 4.0)
- [Artoriuz/glsl-chroma-from-luma-prediction](https://github.com/Artoriuz/glsl-chroma-from-luma-prediction) — CfL_Prediction
- [an3223/shaders](https://github.com/AN3223/dotfiles/tree/master/.config/mpv/shaders) — nlmeans, nlmeans_luma, hdeband
- bacondither — adaptive sharpen (adasharp_luma)
- [haasn/libplacebo.org](https://libplacebo.org/custom-shaders/#full-example) — filmgrain
