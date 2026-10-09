#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

PATH="$HOME/.moon/bin:$PATH"

if [[ -n "${MCPX_BIN:-}" ]]; then
  mcpx="$MCPX_BIN"
else
  moon build --target native --release cli
  mcpx="$root/_build/native/release/build/cli/cli.exe"
fi

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
            self.send_response(400)
            self.send_header("content-length", "0")
            self.end_headers()
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

echo "[retrieval] Skills and Resources over HTTP and stdio"
python3 - "$mcpx" "$tmp" <<'PY'
import json, os, pathlib, runpy, subprocess, sys, threading, base64
from http.server import HTTPServer, BaseHTTPRequestHandler

binary, tmp = sys.argv[1:]
root = pathlib.Path(tmp)
fixture = root / "retrieval_server.py"
fixture.write_text('''import json, sys, hashlib, base64

def reply(msg):
    meta = msg["params"]["_meta"]
    assert meta["io.modelcontextprotocol/protocolVersion"] == "2026-07-28"
    assert "io.modelcontextprotocol/clientInfo" in meta
    assert "io.modelcontextprotocol/clientCapabilities" in meta
    rpc, params = msg["method"], msg["params"]
    uri = params.get("uri")
    entry = {"uri": "custom://demo/SKILL.md", "frontmatter": {"name": "demo", "description": "Demo", "unknown": {"x": 1}}, "resources": "dynamic"}
    if rpc == "server/discover":
        result = {"resultType": "complete", "supportedVersions": ["2026-07-28"], "capabilities": {"resources": {}, "extensions": {"io.modelcontextprotocol/skills": {"directoryRead": True}}}}
    elif rpc == "skills/list":
        result = {"resultType": "complete", "skills": [entry], "ttlMs": 0, "cacheScope": "public"}
        if "cursor" not in params:
            result["nextCursor"] = ""
        else:
            assert params["cursor"] == ""
    elif uri == "custom://verified/SKILL.md" and rpc in ("skills/get", "resources/read"):
        header = b'---\\nname: verified\\ndescription: Verified\\nunknown: {x: 1}\\n---\\n'
        body = header + b'x' * (16777216 - len(header))
        if rpc == "skills/get":
            files = [{"uri": uri, "digest": "sha256:" + hashlib.sha256(body).hexdigest(), "size": len(body)}]
            files += [{"uri": "custom://verified/f" + str(i), "digest": "sha256:" + hashlib.sha256(b'').hexdigest(), "size": 0} for i in range(511)]
            result = {"resultType":"complete", "ttlMs":0, "cacheScope":"private", "skill":{"uri":uri,"frontmatter":{"name":"verified","description":"Verified","unknown":{"x":1}},"resources":files}}
        else:
            result = {"resultType":"complete", "ttlMs":0, "cacheScope":"private", "contents":[{"uri":uri,"blob":base64.b64encode(body).decode()}], "unknown": True}
    elif rpc == "skills/get" and uri == entry["uri"]:
        result = {"resultType": "complete", "skill": entry, "ttlMs": 0, "cacheScope": "public"}
    elif rpc == "resources/directory/read" and uri == "custom://demo":
        result = {"resultType": "complete", "resources": [{"uri": "custom://demo/file", "name": "file", "unknown": True}]}
        if "cursor" not in params:
            result["nextCursor"] = ""
        else:
            assert params["cursor"] == ""
    elif rpc == "resources/read":
        result = {"status": "error", "resultType": "complete", "contents": [{"uri": uri, "text": "Error: ordinary resource"}, {"uri": "custom://blob", "blob": "AAE="}], "ttlMs": 0, "cacheScope": "private", "unknown": True}
    else:
        return {"jsonrpc": "2.0", "id": msg["id"], "error": {"code": -32602, "message": "not found"}}
    return {"jsonrpc": "2.0", "id": msg["id"], "result": result}

if __name__ == "__main__":
    methods = []
    verified = False
    for line in sys.stdin:
        assert not verified, "unexpected request after verified root"
        msg = json.loads(line)
        methods.append(msg["method"])
        response = reply(msg)
        if msg["method"] == "resources/read" and msg["params"].get("uri") == "custom://verified/SKILL.md":
            assert methods == ["server/discover", "skills/get", "resources/read"]
            response["result"]["calls"] = len(methods)
            verified = True
        print(json.dumps(response), flush=True)
''')
reply = runpy.run_path(str(fixture))["reply"]
requests = []
class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.headers.get("transfer-encoding", "").lower() == "chunked":
            chunks = []
            while True:
                size = int(self.rfile.readline().strip(), 16)
                if size == 0:
                    self.rfile.readline()
                    break
                chunks.append(self.rfile.read(size))
                self.rfile.read(2)
            body = b"".join(chunks)
        else:
            body = self.rfile.read(int(self.headers["content-length"]))
        msg = json.loads(body)
        assert self.headers["Mcp-Method"] == msg["method"]
        assert self.headers["MCP-Protocol-Version"] == "2026-07-28"
        assert "Mcp-Session-Id" not in self.headers
        requests.append(msg)
        if self.path == "/private" and self.headers.get("Authorization") != "Bearer secret":
            status, data = 401, b'{}'
        else:
            response = reply(msg)
            if self.path == "/generic" and msg["method"] == "server/discover":
                response["result"]["capabilities"] = {"resources": {}}
            status = 400 if "error" in response else 200
            if msg["method"] == "skills/list":
                data = ('data: {"jsonrpc":"2.0","method":"notifications/progress"}\n\n' + "data: " + json.dumps(response) + "\n\n").encode()
            else:
                data = json.dumps(response).encode()
        self.send_response(status)
        self.send_header("content-type", "text/event-stream" if msg["method"] == "skills/list" else "application/json")
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, *_):
        pass
server = HTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
url = f"http://127.0.0.1:{server.server_port}"
env = os.environ.copy()
env.update(HOME=str(root / "home"), XDG_CONFIG_HOME=str(root / "config"), MCPX_SKILLS_AUTH="Bearer secret")
config = root / "config/mcpx/mcp.jsonc"
config.write_text(json.dumps({"mcpServers": {
    "local": {"transport": "stdio", "command": "python3", "args": ["-u", str(fixture)]},
    "private": {"transport": "http", "url": url + "/private", "headers": {"Authorization": "${MCPX_SKILLS_AUTH}"}},
    "legacy": {"transport": "stdio", "command": "/must/not/spawn", "protocol": {"mode": "stateful"}},
    "warm": {"transport": "stdio", "command": "/must/not/spawn", "lifecycle": {"mode": "keep-alive"}},
}}))
def call(*args, success=True):
    proc = subprocess.run([binary, *args], env=env, input="ignored stdin", text=True, capture_output=True, timeout=30)
    assert proc.returncode == (0 if success else 2), (args, proc.returncode, proc.stdout, proc.stderr)
    assert not proc.stderr, proc.stderr
    return proc.stdout.strip()
try:
    for target in [url + "/read", "local"]:
        listing = json.loads(call("skills", target, "--json"))
        assert listing["origin"].startswith("url:sha256:" if target.startswith("http") else "config:")
        pages = listing["result"]["pages"]
        assert len(pages) == 2 and pages[0]["nextCursor"] == ""
        assert pages[0]["skills"][0]["frontmatter"]["unknown"] == {"x": 1}
        assert "demo" in call("skills", target)
        requests.clear()
        entry = json.loads(call("skills", target, "custom://demo/SKILL.md", "--json"))
        assert entry["result"]["skill"]["resources"] == "dynamic"
        if target.startswith("http"):
            assert [r["method"] for r in requests] == ["server/discover", "skills/get"]
        requests.clear()
        verified = json.loads(call("skills", target, "custom://verified/SKILL.md", "--verify", "--json"))
        assert verified["verified"] and len(verified["entry"]["resources"]) == 512
        assert len(base64.b64decode(verified["result"]["contents"][0]["blob"])) == 16777216
        if target.startswith("http"):
            assert [r["method"] for r in requests] == ["server/discover", "skills/get", "resources/read"]
        else:
            assert verified["result"]["calls"] == 3
        call("skills", target, "custom://demo/SKILL.md", "--verify", success=False)
        directory = json.loads(call("resources", target, "custom://demo", "--json"))["pages"]
        assert len(directory) == 2 and directory[0]["resources"][0]["unknown"]
        content = json.loads(call("resources", target, "custom://demo/file", "--json"))
        assert content["status"] == "error" and content["unknown"] and len(content["contents"]) == 2
        text = call("resources", target, "custom://demo/file")
        assert text.startswith("Error: ordinary resource") and "AAE=" in text
        call("skills", target, "custom://unknown/SKILL.md", success=False)
    requests.clear()
    call("resources", url + "/generic", "other://opaque")
    assert [r["method"] for r in requests] == ["server/discover", "resources/read"]
    call("skills", "private", "--json")
    assert "auth" in call("skills", url + "/private", success=False)
    assert "stateful" in call("skills", "legacy", success=False)
    assert "ephemeral" in call("resources", "warm", "u", success=False)
    # Leave stdin open with no bytes: a retrieval command must still exit.
    proc = subprocess.Popen([binary, "skills", url + "/read", "--json"], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        assert proc.wait(timeout=5) == 0
    finally:
        if proc.poll() is None:
            proc.kill(); proc.wait()
        proc.stdin.close(); proc.stdout.close(); proc.stderr.close()
    print("PASS: positional retrieval, pagination, direct get, directory fallback, generic resources, auth, admission and content exit status")
finally:
    server.shutdown(); server.server_close()
PY

echo "OK: e2e passed"
