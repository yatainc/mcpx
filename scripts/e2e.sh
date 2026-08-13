#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

PATH="$HOME/.moon/bin:$PATH"

moon build --target native --release cli
mcpx="$root/_build/native/release/build/cli/cli.exe"

tmp="$(mktemp -d /tmp/mcpx-e2e.XXXXXX)"
port_file="$tmp/port.txt"

cleanup() {
  if [[ -n "${http_pid:-}" ]]; then
    kill "$http_pid" 2>/dev/null || true
    wait "$http_pid" 2>/dev/null || true
  fi
  HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" "$mcpx" daemon stop >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT

python3 -u - "$port_file" <<'PY' &
import json, sys
from http.server import HTTPServer, BaseHTTPRequestHandler

port_file = sys.argv[1]

def read_body(rfile, headers):
    if headers.get("transfer-encoding", "").lower() == "chunked":
        chunks = []
        while True:
            line = rfile.readline()
            if not line:
                break
            line = line.strip()
            if not line:
                continue
            size = int(line, 16)
            if size == 0:
                while True:
                    tail = rfile.readline()
                    if not tail or tail in (b"\r\n", b"\n"):
                        break
                break
            chunks.append(rfile.read(size))
            rfile.read(2)
        return b"".join(chunks)
    length = int(headers.get("content-length", "0"))
    return rfile.read(length)

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        raw = read_body(self.rfile, {k.lower(): v for k, v in self.headers.items()}).decode("utf-8")
        msg = json.loads(raw) if raw else {}
        method = msg.get("method", "")

        def send_json(obj, code=200):
            data = json.dumps(obj).encode("utf-8")
            self.send_response(code)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        if method == "server/discover":
            send_json({
                "jsonrpc": "2.0",
                "id": msg.get("id", 1),
                "error": {"code": -32000, "message": "Legacy request rejected"},
            }, code=400)
            return

        if method == "initialize":
            send_json({
                "jsonrpc": "2.0",
                "id": msg.get("id", 1),
                "result": {
                    "protocolVersion": "2025-03-26",
                    "capabilities": {},
                    "serverInfo": {"name": "mock"},
                },
            })
            return

        if method == "notifications/initialized":
            self.send_response(202)
            self.end_headers()
            return

        if method == "tools/list":
            send_json({
                "jsonrpc": "2.0",
                "id": msg.get("id", 2),
                "result": {
                    "tools": [
                        {
                            "name": "echo",
                            "description": "Echo text",
                            "inputSchema": {
                                "type": "object",
                                "properties": {"text": {"type": "string"}},
                                "required": ["text"],
                            },
                        }
                    ]
                },
            })
            return

        if method == "tools/call":
            params = msg.get("params", {})
            args = params.get("arguments", {}) or {}
            send_json({
                "jsonrpc": "2.0",
                "id": msg.get("id", 3),
                "result": {"content": [{"type": "text", "text": args.get("text", "")}]},
            })
            return

        self.send_response(500)
        self.end_headers()

    def log_message(self, format, *args):
        pass

httpd = HTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w") as f:
    f.write(str(httpd.server_address[1]))
    f.flush()
httpd.serve_forever()
PY
http_pid=$!

port=""
for _ in {1..50}; do
  if [[ -s "$port_file" ]]; then
    port="$(cat "$port_file")"
    break
  fi
  sleep 0.05
done
if [[ -z "$port" ]]; then
  echo "failed to start mock http server" >&2
  exit 1
fi

url="http://127.0.0.1:$port/mcp"

assert_tool_list() {
  if [[ "$1" != *"Tools"* || "$1" != *"  echo"* ]]; then
    echo "expected tool list with echo, got: $1" >&2
    exit 1
  fi
}

assert_echo_call() {
  if [[ "$1" != "$2" ]]; then
    echo "expected call output '$2', got: $1" >&2
    exit 1
  fi
}

assert_daemon_status() {
  local expected="Daemon: not running"
  if [[ "$2" == "true" ]]; then
    expected="Daemon: running"
  fi
  if [[ "$1" != "$expected" ]]; then
    echo "expected daemon status '$expected', got: $1" >&2
    exit 1
  fi
}

echo "[http] direct URL info"
out="$($mcpx info "$url")"
assert_tool_list "$out"

echo "[http] direct URL call"
out="$($mcpx call "$url" echo '{"text":"hi"}')"
assert_echo_call "$out" "hi"

echo "[config] configured HTTP via ~/.config/mcpx/mcp.jsonc"
config_home="$tmp/config"
mkdir -p "$config_home/mcpx"
cat >"$config_home/mcpx/mcp.jsonc" <<EOF_CFG
{
  // JSONC + trailing comma
  "mcpServers": {
    "srv": { "transport": "http", "url": "$url", },
  },
}
EOF_CFG
out="$(HOME="$tmp/home" XDG_CONFIG_HOME="$config_home" "$mcpx" info srv)"
assert_tool_list "$out"
out="$(HOME="$tmp/home" XDG_CONFIG_HOME="$config_home" "$mcpx" call srv echo '{"text":"cfg"}')"
assert_echo_call "$out" "cfg"

echo "[stdio] configured stdio call"
stdio_py="$tmp/stdio_server.py"
cat >"$stdio_py" <<'PY'
import json, sys

def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()

for line in sys.stdin:
    if not line.strip():
        continue
    msg = json.loads(line)
    method = msg.get("method", "")
    if method == "initialize":
        send({
            "jsonrpc": "2.0",
            "id": msg.get("id", 1),
            "result": {
                "protocolVersion": "2025-03-26",
                "capabilities": {},
                "serverInfo": {"name": "stdio-mock"},
            },
        })
    elif method == "tools/list":
        send({
            "jsonrpc": "2.0",
            "id": msg.get("id", 2),
            "result": {"tools": [{"name":"echo","description":"Echo text","inputSchema":{"type":"object"}}]},
        })
    elif method == "tools/call":
        args = (msg.get("params", {}).get("arguments", {}) or {})
        send({
            "jsonrpc": "2.0",
            "id": msg.get("id", 3),
            "result": {"content":[{"type":"text","text":args.get("text", "")}]},
        })
PY
cat >"$config_home/mcpx/mcp.jsonc" <<EOF_CFG
{
  "mcpServers": {
    "stdio": {
      "transport": "stdio",
      "command": "python3",
      "args": ["-u", "$stdio_py"]
    }
  }
}
EOF_CFG
out="$(HOME="$tmp/home" XDG_CONFIG_HOME="$config_home" "$mcpx" info stdio)"
assert_tool_list "$out"
out="$(HOME="$tmp/home" XDG_CONFIG_HOME="$config_home" "$mcpx" call stdio echo '{"text":"stdio"}')"
assert_echo_call "$out" "stdio"

echo "[daemon] keep-alive stdio call closes captured pipes"
cat >"$config_home/mcpx/mcp.jsonc" <<EOF_CFG
{
  "mcpServers": {
    "stdio": {
      "transport": "stdio",
      "command": "python3",
      "args": ["-u", "$stdio_py"],
      "lifecycle": { "mode": "keep-alive" }
    }
  }
}
EOF_CFG
python3 - "$mcpx" "$tmp/home" "$config_home" <<'PY'
import errno, os, selectors, subprocess, sys, time

mcpx, home, config_home = sys.argv[1:4]
env = os.environ.copy()
env["HOME"] = home
env["XDG_CONFIG_HOME"] = config_home

p = subprocess.Popen(
    [mcpx, "call", "stdio", "echo", '{"text":"pipe"}'],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    env=env,
)
try:
    rc = p.wait(timeout=3.0)
except subprocess.TimeoutExpired:
    p.kill()
    p.wait(timeout=1.0)
    raise SystemExit("mcpx call did not exit")

if rc != 0:
    stdout = p.stdout.read().decode("utf-8", errors="replace")
    stderr = p.stderr.read().decode("utf-8", errors="replace")
    raise SystemExit(
        f"mcpx call exited with {rc}\nstdout: {stdout!r}\nstderr: {stderr!r}"
    )

try:
    os.write(p.stdin.fileno(), b"x")
except BrokenPipeError:
    pass
except OSError as exc:
    if exc.errno != errno.EPIPE:
        raise
else:
    subprocess.run(
        [mcpx, "daemon", "stop"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=env,
        timeout=3.0,
        check=False,
    )
    raise SystemExit(
        "mcpx call stdin pipe still has a reader; daemon likely inherited stdin"
    )
finally:
    p.stdin.close()

selector = selectors.DefaultSelector()
buffers = {"stdout": bytearray(), "stderr": bytearray()}
open_streams = 0
for name, stream in (("stdout", p.stdout), ("stderr", p.stderr)):
    os.set_blocking(stream.fileno(), False)
    selector.register(stream, selectors.EVENT_READ, data=name)
    open_streams += 1

deadline = time.monotonic() + 1.0
while open_streams and time.monotonic() < deadline:
    remaining = max(0.0, deadline - time.monotonic())
    events = selector.select(remaining)
    if not events:
        break
    for key, _ in events:
        chunk = key.fileobj.read()
        if chunk is None:
            continue
        if chunk == b"":
            selector.unregister(key.fileobj)
            open_streams -= 1
            continue
        buffers[key.data].extend(chunk)

if open_streams:
    subprocess.run(
        [mcpx, "daemon", "stop"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=env,
        timeout=3.0,
        check=False,
    )
    raise SystemExit(
        "mcpx call pipes did not reach EOF; daemon likely inherited stdout/stderr"
    )

stdout = buffers["stdout"].decode("utf-8")
stderr = buffers["stderr"].decode("utf-8")
if stdout.strip() != "pipe":
    raise SystemExit(f"expected stdout 'pipe', got: {stdout!r}")
if stderr:
    raise SystemExit(f"expected empty stderr, got: {stderr!r}")
subprocess.run(
    [mcpx, "daemon", "stop"],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    env=env,
    timeout=3.0,
    check=True,
)
PY

echo "[daemon] status smoke"
out="$(HOME="$tmp/home" XDG_CONFIG_HOME="$config_home" "$mcpx" daemon status)"
assert_daemon_status "$out" "false"

echo "OK: e2e passed"
