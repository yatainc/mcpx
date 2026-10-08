#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

build="$(mktemp -d "${TMPDIR:-/tmp}/mcpx-api.XXXXXX")"
trap 'rm -rf "$build"' EXIT
moon info --target all --frozen --target-dir "$build"

# --target inspects interfaces, but moon info only writes the canonical backend.
# Use fresh output so a previously supported backend cannot supply stale files.
# Select native when supported, then JS/Wasm for portable-only packages.
python3 - "$build" <<'PY'
from pathlib import Path
import shutil
import sys

root = Path.cwd()
build = Path(sys.argv[1])
written = set()
for target in ['native', 'js', 'wasm', 'wasm-gc']:
    check = build / target / 'debug' / 'check'
    for interface in sorted(check.rglob('*.mbti')):
        package = interface.parent.relative_to(check)
        if not package.parts or package.parts[0].startswith('.'):
            continue
        if interface.name != package.name + '.mbti':
            continue
        if package in written or not (root / package / 'moon.pkg').is_file():
            continue
        shutil.copyfile(interface, root / package / 'pkg.generated.mbti')
        written.add(package)
PY
