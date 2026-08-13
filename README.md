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

For stdio, omitted mode and explicit `stateful` preserve initialize-era behavior.
Explicit `auto` and `stateless` are rejected until safe sibling-process probing is
implemented. This is independent of stdio `lifecycle.mode`, which only controls
process reuse.

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

```sh
moon fmt
moon test
moon check --target native --deny-warn --fmt
moon check --target wasm-gc
moon check --target js
bash scripts/e2e.sh
bash scripts/benchmark.sh
```

## Roadmap

- [x] support MCP `2026-07-28` discovery, `tools/list`, and `tools/call` over HTTP
- [ ] add safe MCP `2026-07-28` stdio negotiation
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
