#!/usr/bin/env bash
# Replace the generated .mooncakes directory and print the pinned registry home.
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
deps=$(nix build --no-link --print-out-paths .#moon-dependencies)
rm -rf -- .mooncakes
cp -R "$deps/.mooncakes" .
chmod -R u+w .mooncakes
printf '%s\n' "$deps"
