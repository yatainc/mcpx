///|
test "bench config JSONC decode and env resolution" (it : @bench.T) {
  let text =
    #|{
    #|  // representative mcpx config
    #|  "mcpServers": {
    #|    "github": {
    #|      "transport": "http",
    #|      "url": "https://${GITHUB_HOST}/mcp",
    #|      "headers": { "Authorization": "Bearer ${GITHUB_TOKEN}" },
    #|      "auth": {
    #|        "type": "oauth",
    #|        "clientId": "${GITHUB_CLIENT_ID}",
    #|        "clientSecret": "${GITHUB_CLIENT_SECRET}",
    #|        "metadataUrl": "https://${GITHUB_HOST}/.well-known/oauth-authorization-server",
    #|        "scopes": ["repo", "read:user"],
    #|      },
    #|    },
    #|    "local": {
    #|      "transport": "stdio",
    #|      "command": "${NODE_BIN}",
    #|      "args": ["${SERVER_JS}", "--token", "${API_TOKEN}"],
    #|      "env": { "API_TOKEN": "${API_TOKEN}" },
    #|      "cwd": "${PROJECT_DIR}",
    #|      "lifecycle": { "mode": "keep-alive", "idleTimeoutMs": 300000 },
    #|    },
    #|  },
    #|}
  let env = {
    "GITHUB_HOST": "mcp.github.com",
    "GITHUB_TOKEN": "token-1",
    "GITHUB_CLIENT_ID": "client-1",
    "GITHUB_CLIENT_SECRET": "secret-1",
    "NODE_BIN": "/usr/local/bin/node",
    "SERVER_JS": "/srv/mcp/server.js",
    "API_TOKEN": "secret-token",
    "PROJECT_DIR": "/srv/mcp",
  }
  it.bench(() => {
    let normalized = @config.normalize_jsonc(text) catch {
      _ => abort("unexpected JSONC error")
    }
    let config = @config.decode_mcpx_config(@json.parse(normalized)) catch {
      _ => abort("unexpected config error")
    }
    let github = config.servers.get("github").unwrap()
    let stdio_server = config.servers.get("local").unwrap()
    let resolved_github = @config.resolve_server_env(github, env).unwrap()
    let resolved_stdio = @config.resolve_server_env(stdio_server, env).unwrap()
    it.keep((resolved_github.url, resolved_stdio.command))
  })
}

///|
test "bench dotenv parse and merge representative env" (it : @bench.T) {
  let text =
    #|GITHUB_TOKEN=token-1
    #|GITHUB_CLIENT_ID=client-1
    #|GITHUB_CLIENT_SECRET=secret-1
    #|NODE_BIN=/usr/local/bin/node
    #|SERVER_JS=/srv/mcp/server.js
    #|API_TOKEN=secret-token
    #|PROJECT_DIR=/srv/mcp
  let process_env = { "GITHUB_TOKEN": "process-token" }
  it.bench(() => {
    let parsed = @config.parse_dotenv(text).unwrap()
    it.keep(@config.merge_env(parsed, process_env).length())
  })
}
