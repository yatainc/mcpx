# mcpx

Lightweight CLI / JS Runtime for the Model Context Protocol built with MoonBit.
Designed for small bundle size and low memory usage, with short-lived, stateless-by-default MCP discovery and tool calls.

## Installation

```sh
curl -fsSL https://raw.githubusercontent.com/yatainc/mcpx/main/install.sh | sh
```

Run directly:

```sh
nix run --accept-flake-config github:yatainc/mcpx -- --help
```

## Usage

```sh
mcpx
mcpx --help
mcpx --version
mcpx info
mcpx info <server|url> [tool]
mcpx search <pattern>
mcpx call <server|url> <tool> [arguments-json]
mcpx skills <server|url> [uri] [--json]
mcpx resources <server|url> <uri> [--json]
mcpx auth <server> [--no-browser] [--json]
mcpx auth <server> --code <code> --state <state>
mcpx daemon
mcpx daemon <status|stop>
```

Direct remote MCP URL, no config:

```sh
mcpx info https://mcp.example.com/mcp
mcpx call https://mcp.example.com/mcp search '{"q":"moonbit"}'
```

Configured server:

```sh
mcpx info github
mcpx search search
mcpx call github search '{"q":"moonbit"}'
```

CLI output is human-readable by default. MCP text-content results are printed
directly; non-text results are printed under `Result:`. `auth --no-browser --json`
remains JSON for copy/paste and automation handoff.

## Skills and Resources

```sh
mcpx skills docs-server
mcpx skills docs-server custom://demo/SKILL.md --json
mcpx resources docs-server custom://demo
mcpx resources docs-server custom://demo/references/guide.md --json
```

`skills` lists all available pages, or gets one entry directly when given a URI.
A listing can be empty or partial; direct get does not require a preceding list.
Skill entries retain their frontmatter and manifest, including unknown fields.

`resources` reads ordinary resource contents, without requiring the Skills
extension. If the server declares `directoryRead: true`, it first tries a direct
child listing. Only an initial JSON-RPC `-32602` selects content reading instead;
later-page failures, authentication errors and timeouts are errors. Directories
are nonrecursive. URIs and pagination cursors are sent unchanged.

`--json` returns the parsed result for get/content, or `{"pages":[...]}` for
lists/directories, preserving per-page metadata and unknown fields. Normal lists
show names and URIs; content reads print text and retain binary items as JSON.
Entry get returns JSON in either mode. Parsing follows standard MoonBit JSON
semantics, not exact source number spelling.

These commands require MCP `2026-07-28` and use modern discovery even when stdio
protocol mode is omitted. Explicit `stateful` mode and keep-alive stdio targets
are rejected. Each native CLI command has one 30-second deadline across discovery,
pagination and fallback. They do not implement separate response-size or total
receive-byte quotas.

Results are untrusted server data, not loaded or verified Skills. There is no
YAML parsing, digest verification, file saving, cache, approval or execution of
Skill instructions. Existing Tool cache and keep-alive behavior is unchanged.

## Config

`mcpx` reads user config from `~/.config/mcpx/mcp.jsonc`.
`~/.config/mcpx/mcp.json` is also supported when the JSONC file is not
present, but `mcp.jsonc` wins when both exist.

Add `"$schema"` for editor autocompletion and validation:

```jsonc
{
  "$schema": "https://raw.githubusercontent.com/yatainc/mcpx/main/schema.json",
  "mcpServers": {
    // Required: server name used by `mcpx info/call/search`.
    "github": {
      // Required: "http" for remote MCP endpoints.
      "transport": "http",
      // Required for http: MCP endpoint URL.
      "url": "https://mcp.github.com/mcp",

      // Optional: extra HTTP headers; ${VAR} is supported.
      "headers": {
        "Authorization": "Bearer ${GITHUB_TOKEN}"
      },

      // Optional: OAuth metadata used by `mcpx auth github`.
      "auth": {
        "type": "oauth",
        "clientId": "${GITHUB_CLIENT_ID}",
        "clientSecret": "${GITHUB_CLIENT_SECRET}",
        "metadataUrl": "https://mcp.github.com/.well-known/oauth-authorization-server"
      },

      // Optional: visible/callable tool allowlist. Glob only.
      "allowedTools": ["read_*", "list_*", "search_*"],
      // Optional: denylist applied last; wins conflicts.
      "disabledTools": ["delete_*", "write_*", "create_*"]
    },

    // Required: another server name.
    "local": {
      // Required: "stdio" for child-process MCP servers.
      "transport": "stdio",
      // Required for stdio: executable.
      "command": "node",
      // Optional: executable arguments.
      "args": ["/path/to/server.js"],

      // Optional connection handling. HTTP defaults to "auto".
      // For stdio, omit this or use "stateful" for the current release.
      "protocol": {
        "mode": "stateful"
      },

      // Optional: process env; ${VAR} is supported.
      "env": {
        "API_TOKEN": "${API_TOKEN}"
      },
      // Optional: working directory.
      "cwd": "/path/to/project",

      // Optional: keep expensive stdio servers warm.
      "lifecycle": {
        "mode": "keep-alive",
        "idleTimeoutMs": 300000
      }
    }
  }
}
```

### MCP protocol modes

`protocol.mode` controls the MCP connection lifecycle. Accepted values are `auto`,
`stateful`, and `stateless`; the resulting protocol version determines request
encoding.

HTTP defaults to `auto`: it tries MCP `2026-07-28` discovery and falls back to the
initialize lifecycle only for explicit legacy signals. `stateful` selects the
initialize lifecycle directly and retains a server-issued session ID. `stateless`
requires MCP `2026-07-28`, never sends a session ID, and does not silently downgrade
to an initialize-era protocol.

For stdio Tool commands, omitted mode and explicit `stateful` preserve initialize-era behavior.
Explicit `auto` tries `server/discover` and falls back on JSON-RPC method-not-found;
`stateless` requires MCP `2026-07-28`. This is independent of stdio
`lifecycle.mode`, which only controls process reuse.

### Environment values

`.env` uses simple `KEY=value` lines. Process environment wins over `.env`.
Only `${VAR}` interpolation is supported; fallback syntax such as
`${VAR:-fallback}` is intentionally rejected.

Interpolation applies to HTTP, OAuth static client fields, and stdio launch fields.

### Search

`mcpx search <pattern>` searches configured server names and descriptions.
No server connections are needed — it reads config only. Results show the
top 5 matches ranked by relevance (exact > prefix > contains).

### Keep-alive daemon

Public daemon commands are intentionally limited:

```sh
mcpx daemon status
mcpx daemon stop
```

Keep-alive stdio servers start the daemon automatically when needed. If config or
environment values change and an existing stdio process should be discarded, run
`mcpx daemon stop`.

## OAuth

OAuth is explicit: `info` and `call` never open a browser unexpectedly. When auth
is required, the CLI returns a hint such as `mcpx auth <server>`.

```sh
mcpx auth github
mcpx auth github --no-browser --json
mcpx auth github --code CODE --state STATE
```

`--no-browser --json` prints an authorization URL, callback URL, and state. Open
the URL manually, then complete with `--code` and `--state`.

Credentials are stored in `~/.config/mcpx/credentials.json`. The PKCE verifier is
stored machine-managed and is not printed.

## Development

Nix pins the development toolchain. Moon resolves library versions from
`moon.mod`; there is no duplicate Nix manifest or checked-in registry snapshot.
The first registry update/build requires network access to fetch missing dependencies.

`nix build` fetches dependencies through Moon in a separate fixed-output step,
then builds offline. When changing dependencies, update the single `outputHash`
in `package.nix` (set it to `lib.fakeHash`, build, and use the reported hash).
The Nix application package and binary cache remain available.

```sh
nix develop
moon update
moon build --target native cli
moon fmt
moon check --target all --frozen --warn-list +73 --deny-warn
bash scripts/update-api.sh
moon test --target native --frozen --warn-list +73 --deny-warn --no-parallelize
moon test --target js --frozen --warn-list +73 --deny-warn
moon test --target wasm-gc --frozen --warn-list +73 --deny-warn
bash scripts/e2e.sh
bash scripts/benchmark.sh
```

Tools definitions, pagination, catalog validation, and refresh/retry decisions
live in portable `core/tools`. `core/protocol` owns common JSON-RPC and MCP
metadata; `core/http` owns HTTP negotiation and exchange. Native stdio owns its
connection, request IDs, locking, and operation timeout independently of HTTP.

The native `cli/tools` package executes resolved Tool commands and formats their
results. The CLI root resolves config, environment, and OAuth and routes commands;
it has a single execution path, not a separate JSON command-plan API.
Set `MCPX_BIN=/path/to/mcpx` when running `scripts/e2e.sh` to test an existing
artifact instead of rebuilding the checkout.

`bash scripts/update-api.sh` refreshes generated interfaces from fresh compiler
output: native where supported, then JS/Wasm. Unlike `moon info --target`, it also
updates platform-only packages whose canonical Wasm interface is unavailable.

The benchmark script includes moved Tools and SSE cases. CLI call benchmarks now
measure parsing only, since the unused command-plan renderer was removed; their
timings are not comparable to the previous parse-and-render workload.

## Roadmap

- [x] support MCP `2026-07-28` discovery, `tools/list`, and `tools/call` over HTTP
- [x] add MCP `2026-07-28` stdio negotiation
- [ ] publish the JS build as a library package
- [ ] provide an npm package that downloads/installs the native CLI

Detail in: `bit issue list`

## Prior Art

- [openclaw/mcporter](https://github.com/openclaw/mcporter)
- [evantahler/mcpx](https://github.com/evantahler/mcpx)
- [AIGC-Hackers/mcpx](https://github.com/AIGC-Hackers/mcpx)
- [philschmid/mcp-cli](https://github.com/philschmid/mcp-cli)

## License
MIT
