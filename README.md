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
mcpx skills <server|url> [uri] [--verify] [--json]
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
mcpx skills docs-server custom://demo/SKILL.md --verify --json
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

Skills JSON uses `{"origin":...,"result":...}`; list results contain `pages`.
The origin is client-assigned: `config:sha256:<hash>` identifies the selected
config path and server name; `url:sha256:<hash>` identifies a direct URL. It is
never `serverInfo.name` and does not expose URL credentials. Entries and
pages preserve unknown fields. Human listings show origin, names and URIs; no
name is used as an identifier. Generic Resources JSON remains the parsed content
result or `{"pages":[...]}` for directories. Text reads print text and binary
items remain JSON. Parsing uses standard MoonBit JSON numeric semantics.

These commands require MCP `2026-07-28` and use modern discovery even when stdio
protocol mode is omitted. Explicit `stateful` mode and keep-alive stdio targets
are rejected. Each native CLI command has one 30-second deadline across discovery,
pagination, verification and fallback. Retrieval limits are 128 MiB per decoded
HTTP body/stdio frame, 256 MiB cumulatively per CLI command, 1,000 pages and
100,000 items. Cursors remain opaque; a repeated continuation cursor is an error.
These are not total-wire/header or hard heap guarantees. HTTP framing and
compression are handled by the standard client. Responses are buffered within
these limits, not terminated early at the first final SSE event.

`--verify` requires a Skill URI. It gets and fixes one entry, checks its manifest
(512 resources and 16 MiB total declared file size inclusive), then reads only
root `SKILL.md`. Raw byte length, SHA-256, UTF-8 and the complete YAML frontmatter
are checked. YAML parsing uses an external parser; graph-to-JSON conversion
rejects cycles and limits depth to 128, visits to 1,000,000 and logical output to
96 MiB. These additional complexity policies are not a claim that every valid
16 MiB YAML document is accepted. Dynamic manifests cannot be verified.
Verification confirms consistency with the same server's unsigned entry, not
trust, authorship, user approval or activation. JSON verification output carries
`origin`, `skillUri`, `verified`, `entry` and the original resource `result`.

The library's `Source::hold(uri)` keeps an independent entry and a fixed RPC peer.
`HeldSkill::read(uri)` refuses unlisted files before I/O; it verifies supporting
bytes on demand without applying nested frontmatter. `same_content` compares
origin, Skill URI and the complete URI/digest set; failures never refresh the
entry silently. Native adapters provide `http_mcp_skill_source` and
`StdioMcpClient::skill_source`. A shared receive budget is for one finite operation,
not a reusable client's lifetime. Budget-bearing stdio connections require
explicit `Stateless` mode; legacy modes and fallback are rejected before spawn.
Custom transports own their I/O limits and serialization. The host must provide unique nonsecret origin labels, retain the
snapshot for its acting window, preserve origin in model context, and explicitly
handle approval/reapproval, cross-origin consent and execution permissions.
`allowed-tools` and other content never grant permissions here. A manifest's
hidden-file completeness remains a server assertion; unlisted reads are rejected.

There is no file saving, Skill cache, approval store, activation or execution of
Skill instructions. Ordinary `resources` is not a verified Skill-loading path.
Existing Tool cache, keep-alive and legacy transport paths remain separate.

## Config

`mcpx` automatically reads configuration from two roots:

- User: `$XDG_CONFIG_HOME/mcpx` when `XDG_CONFIG_HOME` is absolute, otherwise
  `~/.config/mcpx`.
- Project: the Git working-tree root containing the invoking directory.
  Linked worktrees and submodules use their own roots.

At **each root**, the first existing file wins, in this order:
`mcp.jsonc`, `mcp.json`, `.mcp.jsonc`, `.mcp.json`. Only one file per root is read.
JSONC comments and trailing commas are accepted for all four names. A selected
unreadable or invalid file is an error, not a reason to try another file.

Server maps are combined by name: **project replaces the whole user definition**.
Missing project fields do not inherit user auth, env or tool filters. Nested
configs do not shadow the Git-root config. Outside Git, or when Git is not
installed, only user config is used; other Git discovery failures are errors.
Direct URLs, help/version and daemon control do not load project config.

For example, an existing project `.mcp.json` can be used unchanged:

```json
{
  "mcpServers": {
    "foldkit-devtools": {
      "command": "node",
      "args": ["./node_modules/@foldkit/devtools-mcp/dist/server.js"]
    }
  }
}
```

`transport` is inferred from `command` (stdio) or `url` (HTTP); exactly one is
required, and any explicit transport must agree. This is the shared
`mcpServers` subset, not a promise of every editor's configuration dialect.
Project stdio servers default to the Git root as cwd; relative `cwd` values
resolve there after environment expansion. User entries use the invoking cwd.
Arguments are not rewritten. Executables use the effective caller/server `PATH`,
including when a daemon was started in another directory or shell.

Project config is automatic and can select executable commands and credentials;
use it only in projects you trust. There is no approval prompt or trust database.
`mcpx info` lists configured server names and descriptions without starting servers.

Add `"$schema"` for editor autocompletion and validation:

```jsonc
{
  "$schema": "https://raw.githubusercontent.com/yatainc/mcpx/main/schema.json",
  "mcpServers": {
    // Required: server name used by `mcpx info/call/search`.
    "github": {
      // Optional: inferred as "http" from url.
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
      // Optional: inferred as "stdio" from command.
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

Credentials remain in the user `credentials.json`, but are scoped to the selected
config file and server name and are used only for the exact endpoint URL. Run
`mcpx auth <server>` from the project whose server you intend to authenticate;
manual code completion must use the same source and endpoint. Name-only
credentials from earlier versions are not reused: authenticate again, and run
`mcpx daemon stop` to replace any old daemon after upgrading.

Keep-alive reuses only matching source and effective launch conditions, including
environment values and protocol mode. It does not guarantee application readiness
or retry failed tool calls; relay/server readiness remains the server's concern.

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

Only the user config directory's `.env` is read, using simple `KEY=value` lines;
there is no project `.env` discovery. Process environment wins over `.env` for
interpolation. Child processes inherit the invoking environment plus resolved
server `env`; the dotenv file is not exported wholesale.
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

Keep-alive stdio servers start the daemon automatically when needed. Changed
launch conditions select a different process; old entries retain their configured
idle lifetime. Run `mcpx daemon stop` to discard all retained processes.

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
