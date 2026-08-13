# Minimal Moon registry snapshot

This directory contains only the registry records required by the project `moon.mod`.
It replaces the global `https://mooncakes.io/git/index` checkout so Nix builds
are deterministic across case-sensitive and case-insensitive filesystems and
never fetch the registry when evaluating or building mcpx.

Source revision: `67b0102dad176a6740ae3af60f34966632ce7c30`

Included records:

- `moonbitlang/async` `0.20.5`
- `moonbitlang/x` `0.4.49`

When changing a dependency version in `moon.mod`, copy its exact JSON-line
record from the pinned Moon registry into the corresponding `.index` file.
Transitive dependencies must be included as additional records when present.
