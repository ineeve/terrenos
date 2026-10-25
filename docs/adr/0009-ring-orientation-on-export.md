# 0009 — Ring orientation is fixed on export, not in storage

- **Status:** accepted (M1, T1.8, 2026-10-25)
- **Refines:** SPEC.md §3.5 VAL-4

## Decision

VAL-4 ("ring closure and orientation (RFC 7946): fix automatically") is
applied when a boundary leaves the app, not when it is saved:

- Stored rings keep the order the user gave the vertices, and stay open
  (SPEC.md §7.1).
- Exports call `orientedForExport` (`lib/core/editing/boundary_fixes.dart`):
  outer rings counter-clockwise, holes clockwise. GeoJSON and KML writers
  close each ring by repeating its first position.

## Why

Vertex labels follow their position in the ring (`V1`, `V2`…), and in the
field vertices are surveyed in that order. Reversing a clockwise ring on
save would silently turn V2 into V4. The orientation only matters to other
software, and only exported files reach it.

## Consequences

- The export task (T5.x, EXP-1) must use `orientedForExport`; its tests
  should check the orientation of exported rings.
- Area, crossings and the other checks don't depend on orientation, so
  validation is unchanged.
