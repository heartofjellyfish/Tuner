# Instrument artwork verification — 2026-10-04

- Native Canvas headstocks for all eight instruments; full silhouettes only in picker.
- Four-string bass uses four inline keys. Five/six-string bass use split key layouts to keep targets separate.
- Mandolin courses have two physical posts and string paths each; both paths share selected/completed feedback.
- Five-string banjo drone begins at side peg below nut. Four/six-string presets use full-length strings.
- Bowed scrolls, lateral peg handles and unfretted necks replace generic headstock plus ellipses.
- All selection regions at least44pt high; bass inline keys and right-hand labels share full-row hit target.
- No change to pitch detection, input signal data, success sounds or calibration.

## Checks
- iPhone16e: every instrument standard tuning label, every string/course tap-lock-unlock, no main-page scroll, target bounds: passed.
- iPhone16e: 5/6-string bass tap-lock-unlock: passed.
- iPhoneSE3: every instrument standard tuning and every target: passed.
- iPhoneSE3: 5/6-string bass tap-lock-unlock: passed.
- Both devices: fixed viewport and guitar8-string selection: passed.
- iPhone16e: completed string retention, drift clears mark and reset: passed.
- Release device build: passed.
- Visual review: eight instrument screenshots, picker top/bottom, revised bowed scroll proportions, paired mandolin strings, banjo sidepeg.

Gallery contains final large-screen native UI screenshots. UI tests use synthetic preview input; live microphone tuning accuracy was not changed or re-measured.
