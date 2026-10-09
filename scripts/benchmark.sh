#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

PATH="$HOME/.moon/bin:$PATH"

bench_packages=(
  core/tools
  core/http
  core/protocol
  core/config
  cli
  wasm
)

echo "[moon bench] portable hot paths"
bench_args=()
for pkg in "${bench_packages[@]}"; do
  bench_args+=(--package "$pkg")
done
moon bench --target native --release "${bench_args[@]}"

echo
echo "[build] release artifacts"
moon build --target native --release cli >/dev/null
moon build --target js --release wasm >/dev/null
moon build --target wasm-gc --release wasm >/dev/null

native_bin="$root/_build/native/release/build/cli/cli.exe"
wasm_js="$root/_build/js/release/build/wasm/wasm.js"
wasm_wasm="$root/_build/wasm-gc/release/build/wasm/wasm.wasm"

artifact_json="$(
  python3 - "$native_bin" "$wasm_js" "$wasm_wasm" <<'PY'
import gzip, json, os, sys

native_bin, wasm_js, wasm_wasm = sys.argv[1:4]

def metric(path):
    data = open(path, "rb").read()
    gzip_bytes = len(gzip.compress(data, compresslevel=9))
    return {
        "path": path,
        "bytes": len(data),
        "kib": round(len(data) / 1024, 2),
        "gzipBytes": gzip_bytes,
        "gzipKib": round(gzip_bytes / 1024, 2),
    }

print(json.dumps({
    "nativeReleaseBinary": metric(native_bin),
    "wasmJsRelease": metric(wasm_js),
    "wasmWasmGcRelease": metric(wasm_wasm),
}, separators=(",", ":")))
PY
)"
echo "$artifact_json"

if [[ "${MCPX_BENCH_ENFORCE:-0}" == "1" ]]; then
  python3 - "$artifact_json" <<'PY'
import json, os, sys

metrics = json.loads(sys.argv[1])
limits = {
    "nativeReleaseBinary.bytes": int(os.environ.get("MCPX_MAX_NATIVE_BYTES", 10 * 1024 * 1024)),
    "wasmJsRelease.bytes": int(os.environ.get("MCPX_MAX_EMBEDDED_JS_BYTES", 512 * 1024)),
    "wasmJsRelease.gzipBytes": int(os.environ.get("MCPX_MAX_EMBEDDED_JS_GZIP_BYTES", 80 * 1024)),
    "wasmWasmGcRelease.bytes": int(os.environ.get("MCPX_MAX_EMBEDDED_WASM_BYTES", 128 * 1024)),
    "wasmWasmGcRelease.gzipBytes": int(os.environ.get("MCPX_MAX_EMBEDDED_WASM_GZIP_BYTES", 64 * 1024)),
}

failures = []
for key, limit in limits.items():
    artifact, field = key.split(".")
    value = metrics[artifact][field]
    if value > limit:
        failures.append(f"{key}={value} > {limit}")

if failures:
    print("size budget failed:", "; ".join(failures), file=sys.stderr)
    sys.exit(1)
PY
fi

echo
echo "[cli startup] mcpx daemon status"
tmp="$(mktemp -d /tmp/mcpx-bench.XXXXXX)"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT
mkdir -p "$tmp/home" "$tmp/config"

MCPX_BIN="$native_bin" MCPX_BENCH_HOME="$tmp/home" MCPX_BENCH_CONFIG="$tmp/config" python3 <<'PY'
import json, os, statistics, subprocess, time

runs = int(os.environ.get("MCPX_BENCH_CLI_RUNS", "30"))
cmd = [os.environ["MCPX_BIN"], "daemon", "status"]
env = os.environ.copy()
env["HOME"] = os.environ["MCPX_BENCH_HOME"]
env["XDG_CONFIG_HOME"] = os.environ["MCPX_BENCH_CONFIG"]

samples = []
for _ in range(runs):
    start = time.perf_counter_ns()
    subprocess.run(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    samples.append((time.perf_counter_ns() - start) / 1_000_000.0)

samples.sort()
p95_index = max(0, min(len(samples) - 1, int(len(samples) * 0.95) - 1))
print(json.dumps({
    "runs": runs,
    "minMs": round(samples[0], 3),
    "p50Ms": round(statistics.median(samples), 3),
    "p95Ms": round(samples[p95_index], 3),
    "maxMs": round(samples[-1], 3),
    "meanMs": round(statistics.mean(samples), 3),
}, separators=(",", ":")))
PY

echo
echo "[memory] RSS benchmarks"
MCPX_BIN="$native_bin" MCPX_BENCH_HOME="$tmp/home" MCPX_BENCH_CONFIG="$tmp/config" python3 <<'PY'
import json, os, re, statistics, subprocess, tempfile

runs = int(os.environ.get("MCPX_BENCH_MEMORY_RUNS", "5"))
bin_path = os.environ["MCPX_BIN"]
remote_url = os.environ.get("MCPX_BENCH_REMOTE_URL", "")
remote_tool = os.environ.get("MCPX_BENCH_REMOTE_TOOL", "resolve-library-id")
remote_args = os.environ.get(
    "MCPX_BENCH_REMOTE_ARGS",
    '{"query":"MoonBit MCP client library","libraryName":"moonbit"}',
)

base_env = os.environ.copy()
base_env["HOME"] = os.environ["MCPX_BENCH_HOME"]
base_env["XDG_CONFIG_HOME"] = os.environ["MCPX_BENCH_CONFIG"]

def time_mode():
    if subprocess.run(["/usr/bin/time", "-l", "true"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        return ("-l", "bytes")
    if subprocess.run(["/usr/bin/time", "-v", "true"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        return ("-v", "kbytes")
    raise RuntimeError("/usr/bin/time does not support -l or -v")

time_flag, unit = time_mode()

def parse_rss(stderr_text):
    if unit == "bytes":
        match = re.search(r"([0-9]+)\s+maximum resident set size", stderr_text)
        if match:
            return int(match.group(1))
    else:
        match = re.search(r"Maximum resident set size \(kbytes\):\s*([0-9]+)", stderr_text)
        if match:
            return int(match.group(1)) * 1024
    raise RuntimeError("failed to parse RSS from /usr/bin/time output: " + stderr_text)

def percentile(sorted_values, ratio):
    index = max(0, min(len(sorted_values) - 1, int(len(sorted_values) * ratio) - 1))
    return sorted_values[index]

def summarize(name, command):
    samples = []
    for _ in range(runs):
        with tempfile.NamedTemporaryFile() as log:
            with open(os.devnull, "wb") as devnull:
                subprocess.run(
                    ["/usr/bin/time", time_flag, *command],
                    env=base_env,
                    stdout=devnull,
                    stderr=log,
                    check=True,
                )
            log.seek(0)
            samples.append(parse_rss(log.read().decode("utf-8", errors="replace")))
    samples.sort()
    return {
        "name": name,
        "runs": runs,
        "rssBytes": {
            "min": samples[0],
            "p50": int(statistics.median(samples)),
            "p95": percentile(samples, 0.95),
            "max": samples[-1],
            "mean": int(statistics.mean(samples)),
        },
        "rssKiB": {
            "min": round(samples[0] / 1024, 2),
            "p50": round(statistics.median(samples) / 1024, 2),
            "p95": round(percentile(samples, 0.95) / 1024, 2),
            "max": round(samples[-1] / 1024, 2),
            "mean": round(statistics.mean(samples) / 1024, 2),
        },
    }

benchmarks = [
    summarize("native daemon status", [bin_path, "daemon", "status"]),
]

if remote_url:
    benchmarks.append(
        summarize("remote MCP info", [bin_path, "info", remote_url])
    )
    benchmarks.append(
        summarize(
            "remote MCP call",
            [bin_path, "call", remote_url, remote_tool, remote_args],
        )
    )

print(json.dumps({"timeMode": time_flag, "benchmarks": benchmarks}, separators=(",", ":")))
PY
