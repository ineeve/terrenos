# 0007 — Drawing with a crosshair instead of dragging vertices

- **Status:** accepted (M1, 2026-10-25)
- **Changes:** SPEC.md REG-1 (drag to move, midpoint handles, long-press to
  delete) and REG-10 (magnifier loupe)

## Decision

Drawing on the map uses a fixed crosshair at the centre of the screen:

- Tap the map to add a vertex there, or pan the map until the crosshair is
  on a corner and tap **Adicionar aqui**.
- Tap a vertex to select it (the map centres on it); pan and tap **Mover
  para aqui** to move it, or **Apagar** to delete it.
- A new vertex goes after the selected one, or at the end.
- Positions snap to other properties' vertices within 10 px (REG-7).
- Coordinates under the crosshair are shown live, with area and perimeter.

## Why

- A finger hides the point being placed; the spec solved this with a loupe
  while dragging. A crosshair has no occlusion at all, so it is more
  precise, and it is the usual pattern in field-survey apps.
- Dragging small markers on a map that also pans is error-prone for older
  users, and gesture conflicts between marker drags and map pans are
  fragile across Android devices.
- Insertion between two vertices is covered by selecting the first and
  adding; precise edits are also possible in the vertex table (§3.4).

## Consequences

- REG-10 (loupe) is not needed and is dropped.
- Midpoint handles are not implemented; "insert into the nearest edge"
  remains available to GPS capture (VTX-8).
