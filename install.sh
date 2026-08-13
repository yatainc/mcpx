#!/bin/sh
set -eu

repo="yatainc/mcpx"
bin_dir="${MCPX_BIN_DIR:-${HOME}/.local/bin}"
version=""

usage() {
  cat <<'USAGE'
Usage:
  install.sh [--version <tag>] [--bin-dir <dir>]

Examples:
  curl -fsSL https://raw.githubusercontent.com/yatainc/mcpx/main/install.sh | sh
  curl -fsSL https://raw.githubusercontent.com/yatainc/mcpx/main/install.sh | sh -s -- --version v0.2.0
  curl -fsSL https://raw.githubusercontent.com/yatainc/mcpx/main/install.sh | sh -s -- --bin-dir /usr/local/bin
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -v|--version)
      version="${2:-}"
      shift 2
      ;;
    -b|--bin-dir)
      bin_dir="${2:-}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "${version}" ]; then
  version="$(
    curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
    | grep -m1 '"tag_name":' \
    | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/'
  )"
fi

if [ -z "${version}" ]; then
  echo "failed to detect latest release tag; retry with --version <tag>" >&2
  exit 1
fi

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) suffix="linux-x64" ;;
  Darwin-arm64) suffix="macos-arm64" ;;
  *)
    echo "unsupported platform: $(uname -s) $(uname -m)" >&2
    exit 1
    ;;
esac

asset="mcpx-${version}-${suffix}.tar.gz"
url="https://github.com/${repo}/releases/download/${version}/${asset}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

archive="${tmp}/${asset}"
curl -fsSL -o "$archive" "$url"

sums="${tmp}/SHA256SUMS"
if ! curl -fsSL -o "$sums" "https://github.com/${repo}/releases/download/${version}/SHA256SUMS"; then
  echo "failed to download SHA256SUMS for ${version}" >&2
  exit 1
fi
expected="$(awk -v asset="$asset" '$2==asset {print $1}' "$sums")"
if [ -z "${expected}" ]; then
  echo "checksum for ${asset} not found in SHA256SUMS" >&2
  exit 1
fi
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$archive" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
else
  echo "neither sha256sum nor shasum is available" >&2
  exit 1
fi
if [ "${expected}" != "${actual}" ]; then
  echo "checksum mismatch for ${asset}" >&2
  echo "  expected: ${expected}" >&2
  echo "  actual:   ${actual}" >&2
  exit 1
fi

tar -xzf "$archive" -C "$tmp"

mkdir -p "$bin_dir"
install -m 0755 "$tmp/mcpx" "$bin_dir/mcpx"

echo "installed: $bin_dir/mcpx"
