# 0001 — Hand-written models for synced documents

- **Status:** accepted (M0)
- **Changes:** SPEC.md §5.1 ("Models: freezed + json_serializable")

## Decision

The synced documents (`PropertyDocument`, `GroupDocument`, `Vertex`,
`GeometryVersion`) and the CRDT primitives are hand-written immutable classes
with explicit `toJson`/`fromJson`. No code generation.

## Why

- The exact JSON shape is part of the sync protocol: documents are hashed as
  canonical JSON (SPEC.md §9.4) and compared byte for byte between phones.
  Hand-written serialisation keeps that shape visible and under review in one
  place, instead of depending on generator settings.
- The models live in pure-Dart `lib/core/` and are few; code generation would
  add build_runner to every change for little gain.

## Consequences

- Equality is defined on canonical JSON, so it matches what sync compares.
- Screens' local view models may still use freezed later if they grow
  numerous; that decision is separate.
