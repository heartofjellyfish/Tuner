# Minimal headstock audit — 2026-10-04

All eight existing native screenshots were inspected at artwork scale before editing.

| Instrument | Finding | Change |
| --- | --- | --- |
| Guitar | Clear silhouette; machine keys have redundant offset outlines. | Remove the secondary key outline. |
| Ukulele | Clear four-string arrangement; same redundant key outlines. | Remove the secondary key outline. |
| Bass | Asymmetric silhouette and clover keys are legible. | Retain existing drawing. |
| Violin | Scroll surfaces look like stacked slices; repeated box edges, holes and double peg rings compete with strings. | Keep silhouette, one scroll cheek edge and carved eye; retain subtle surface shading without outlining every face. Remove decorative holes, duplicate box edges, peg rings and shaft centerlines. |
| Viola | Same excessive construction detail as violin. | Apply the same reduction, retaining its width and tuning. |
| Cello | Same excessive construction detail as violin. | Apply the same reduction, retaining its width and tuning. |
| Banjo | Fifth-string peg is necessary; repeated key outlines are decorative. | Retain drone peg and remove secondary key outlines. |
| Mandolin | Eight strings/posts identify paired courses; keys add avoidable density. | Preserve all paired strings and posts; remove secondary key outlines. |

No target positions, tap regions, outer dimensions or detection behavior change. Selected bowed pegs use their existing contour for the accent instead of an additional concentric ring. Completion checkmarks remain.

Validation: a fresh simulator build passed all eight instrument target/lock/unlock checks and exported all eight reference screens (2 tests, 0 failures). Each exported artwork was visually inspected after the changes. Release device build passed. An initial incremental run executed stale test code; a separate derived-data directory resolved that mismatch without changing assertions.

## Contour correction
The bass now follows the reference's diagonal tuner rail, rounded crown and scooped shoulder; posts follow that rail so strings fall naturally toward the nut. Clover keys use three lobes and a stem rather than four flower petals. Bowed instruments now share continuous boundaries between shaded faces and inked contours, removing the old carved-slice seams. The scroll-to-pegbox join was checked again after correcting a small left-side gap.

Validation: all instrument target checks, extended bass targets and reference captures passed (3 tests). Final join-only correction passed reference captures again. Final violin and bass artwork were inspected from XCTest screenshots. Release build passed.
