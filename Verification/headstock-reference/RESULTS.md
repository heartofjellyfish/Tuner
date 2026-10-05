# Headstock reference correction — 2026-10-04

The previous native drawing oversimplified the approved illustration. This revision traces the bowed scroll into separate carved surfaces and contour paths, with a slanted open pegbox, large round lateral pegs, shafts, recesses and subtle face shading. The reference-space drawing scales uniformly; the neck below the nut is only about 8% of the artwork. Plucked headstocks are wider, bass keys have continuous clover outlines, and decorative fret lines are removed. Banjo retains enough bare neck to show the short fifth-string peg.

The tuning viewport gives the headstock more space. Locking a string does not change the reserved layout height. Existing notes, real microphone input, detection and success audio are unchanged.

## Validation
- iPhone 16e: all 8 instruments, every string/course label, tap/lock/unlock and fixed viewport passed.
- iPhone SE 3: all 8 instruments, every target, five/six-string bass and eight-string guitar passed.
- Completion/progress retention, drift reset and reset action passed on iPhone 16e.
- Custom five-string bowed layout passed on iPhone SE 3.
- Release device build passed.
- Reference screenshots use matched synthetic pitches and zero cents. Artwork crops and geometry are exported directly from XCTest.
- comparison.html shows source and actual artwork in the same 400 × 400 reference coordinates, plus an opacity overlay. The rendering is a hand-traced native interpretation; it is not a pixel-identical raster copy. Fonts, dynamic string highlights and correctness fixes remain native.

An initial 44pt-height assertion failed only because CGRect reported 43.99999999999994; the test now permits 0.01pt floating-point rounding. Hit regions remain 44pt.
