#!/usr/bin/env bash
# Run explicitly with: nix develop --command bash scripts/update-moon-lock.sh
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
lock="$PWD/nix/moon-lock.json"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home"
unset MOON_HOME
mkdir -p "$HOME" "$tmp/project" "$(dirname -- "$lock")"
cp moon.mod "$tmp/project/"
cd -- "$tmp/project"
touch moon.pkg
moon update
moon check --target native
moon tree --json > graph.json
python3 - "$lock" <<'PY'
import json
import os
from pathlib import Path
import sys

registry = Path(os.environ['HOME']) / '.moon/registry/index/user'
graph = json.loads(Path('graph.json').read_text())
if graph['status'] != 'success':
    raise SystemExit(f"Moon could not resolve dependencies: {graph['error']}")
locked = {}
for i, module in enumerate(graph['modules']):
    if i == graph['root']:
        continue
    name, version = module['name'], module['version']
    if module['source']['kind'] != 'registry':
        raise SystemExit(f'Unsupported dependency source: {module}')
    records = [json.loads(line) for line in (registry / f'{name}.index').read_text().splitlines()]
    matches = [record for record in records if record['version'] == version]
    if len(matches) != 1 or not matches[0].get('checksum'):
        raise SystemExit(f'Missing unique checksummed registry record: {name}@{version}')
    if name in locked:
        raise SystemExit(f'Multiple versions cannot share a .mooncakes directory: {name}')
    locked[name] = matches[0]
records = [locked[name] for name in sorted(locked)]
Path(sys.argv[1]).write_text(json.dumps(records, indent=2, sort_keys=True) + '\n')
PY
