///|
test "server config: decodes remote OAuth server shape" {
  let text =
    #|{"mcpServers":{"github":{"transport":"http","url":"https://mcp.github.com/mcp","headers":{"Authorization":"Bearer ${GITHUB_TOKEN}"},"auth":{"type":"oauth","clientId":"${GITHUB_CLIENT_ID}","clientSecret":"${GITHUB_CLIENT_SECRET}","metadataUrl":"https://mcp.github.com/.well-known/oauth-authorization-server"}}}}
  let json = @json.parse(text)
  let config = decode_mcpx_config(json)
  @debug.debug_inspect(
    config,
    content=(
      #|{
      #|  servers: {
      #|    "github": {
      #|      name: "github",
      #|      transport: Http,
      #|      url: Some("https://mcp.github.com/mcp"),
      #|      command: None,
      #|      args: [],
      #|      env: {},
      #|      cwd: None,
      #|      headers: { "Authorization": "Bearer ${GITHUB_TOKEN}" },
      #|      auth: Some(
      #|        {
      #|          kind: OAuth,
      #|          client_id: Some("${GITHUB_CLIENT_ID}"),
      #|          client_secret: Some("${GITHUB_CLIENT_SECRET}"),
      #|          metadata_url: Some("https://mcp.github.com/.well-known/oauth-authorization-server"),
      #|          scopes: [],
      #|        },
      #|      ),
      #|      protocol_mode: None,
      #|      lifecycle: None,
      #|      allowed_tools: [],
      #|      disabled_tools: [],
      #|      description: None,
      #|    },
      #|  },
      #|}

    ),
  )
}

///|
test "server config: decodes protocol connection modes" {
  let decode_mode = mode_text => {
    let text =
      "{\"mcpServers\":{\"server\":{\"transport\":\"http\",\"protocol\":{\"mode\":\"" +
      mode_text + "\"}}}}"
    decode_mcpx_config(@json.parse(text)).servers.get(
      "server",
    ).unwrap().protocol_mode
  }
  inspect(decode_mode("auto") == Some(McpConnectionMode::Auto), content="true")
  inspect(
    decode_mode("stateful") == Some(McpConnectionMode::Stateful),
    content="true",
  )
  inspect(
    decode_mode("stateless") == Some(McpConnectionMode::Stateless),
    content="true",
  )
}

///|
test "server config: applies transport protocol mode defaults" {
  let config = decode_mcpx_config(
    @json.parse(
      "{\"mcpServers\":{\"remote\":{\"transport\":\"http\"},\"local\":{\"transport\":\"stdio\",\"command\":\"server\"}}}",
    ),
  )
  inspect(
    effective_connection_mode(config.servers.get("remote").unwrap()) ==
    McpConnectionMode::Auto,
    content="true",
  )
  inspect(
    effective_connection_mode(config.servers.get("local").unwrap()) ==
    McpConnectionMode::Stateful,
    content="true",
  )
}

///|
test "server config: rejects unsupported protocol connection mode" {
  let mut raised = false
  try
    ignore(
      decode_mcpx_config(
        @json.parse(
          "{\"mcpServers\":{\"server\":{\"transport\":\"http\",\"protocol\":{\"mode\":\"future\"}}}}",
        ),
      ),
    )
  catch {
    _ => raised = true
  } noraise {
    _ => ()
  }
  inspect(raised, content="true")
}

///|
test "server config: resolves env templates in url headers and static OAuth client" {
  let server = mcp_server_config(
    name="github",
    transport=ServerTransport::Http,
    url=Some("https://${GITHUB_HOST}/mcp"),
    headers={ "Authorization": "Bearer ${GITHUB_TOKEN}" },
    auth=Some(
      oauth_server_auth(
        client_id=Some("${GITHUB_CLIENT_ID}"),
        client_secret=Some("${GITHUB_CLIENT_SECRET}"),
      ),
    ),
  )
  let env = {
    "GITHUB_TOKEN": "token-1",
    "GITHUB_HOST": "mcp.github.com",
    "GITHUB_CLIENT_ID": "client-1",
    "GITHUB_CLIENT_SECRET": "secret-1",
  }
  @debug.debug_inspect(
    resolve_server_env(server, env),
    content=(
      #|Ok(
      #|  {
      #|    name: "github",
      #|    transport: Http,
      #|    url: Some("https://mcp.github.com/mcp"),
      #|    command: None,
      #|    args: [],
      #|    env: {},
      #|    cwd: None,
      #|    headers: { "Authorization": "Bearer token-1" },
      #|    auth: Some(
      #|      {
      #|        kind: OAuth,
      #|        client_id: Some("client-1"),
      #|        client_secret: Some("secret-1"),
      #|        metadata_url: None,
      #|        scopes: [],
      #|      },
      #|    ),
      #|    protocol_mode: None,
      #|    lifecycle: None,
      #|    allowed_tools: [],
      #|    disabled_tools: [],
      #|    description: None,
      #|  },
      #|)

    ),
  )
}

///|
test "server config: decodes stdio env/cwd and resolves templates" {
  let text =
    #|{"mcpServers":{"local":{"transport":"stdio","command":"${NODE_BIN}","args":["${SERVER_JS}","--token","${API_TOKEN}"],"env":{"API_TOKEN":"${API_TOKEN}"},"cwd":"${PROJECT_DIR}"}}}
  let config = decode_mcpx_config(@json.parse(text))
  let server = config.servers.get("local").unwrap()
  let env = {
    "NODE_BIN": "/usr/local/bin/node",
    "SERVER_JS": "/srv/mcp/server.js",
    "API_TOKEN": "secret-token",
    "PROJECT_DIR": "/srv/mcp",
  }
  @debug.debug_inspect(
    resolve_server_env(server, env),
    content=(
      #|Ok(
      #|  {
      #|    name: "local",
      #|    transport: Stdio,
      #|    url: None,
      #|    command: Some("/usr/local/bin/node"),
      #|    args: ["/srv/mcp/server.js", "--token", "secret-token"],
      #|    env: { "API_TOKEN": "secret-token" },
      #|    cwd: Some("/srv/mcp"),
      #|    headers: {},
      #|    auth: None,
      #|    protocol_mode: None,
      #|    lifecycle: None,
      #|    allowed_tools: [],
      #|    disabled_tools: [],
      #|    description: None,
      #|  },
      #|)

    ),
  )
}

///|
test "server config: decodes explicit keep-alive lifecycle object" {
  let text =
    #|{"mcpServers":{"playwright":{"transport":"stdio","command":"npx","args":["@playwright/mcp"],"lifecycle":{"mode":"keep-alive","idleTimeoutMs":120000}}}}
  let config = decode_mcpx_config(@json.parse(text))
  let server = config.servers.get("playwright").unwrap()
  @debug.debug_inspect(
    server.lifecycle,
    content=(
      #|Some({ mode: KeepAlive, idle_timeout_ms: Some(120000) })
    ),
  )
}

///|
test "server config: decodes tool filters and applies disabled priority" {
  let text =
    #|{"mcpServers":{"github":{"transport":"http","url":"https://mcp.github.com/mcp","allowedTools":["read_*","list_*","search_*"],"disabledTools":["delete_*","search_private"]}}}
  let config = decode_mcpx_config(@json.parse(text))
  let server = config.servers.get("github").unwrap()
  @debug.debug_inspect(
    (server.allowed_tools, server.disabled_tools),
    content=(
      #|(["read_*", "list_*", "search_*"], ["delete_*", "search_private"])
    ),
  )
  inspect(is_tool_allowed(server, "read_file"), content="true")
  inspect(is_tool_allowed(server, "search_public"), content="true")
  inspect(is_tool_allowed(server, "search_private"), content="false")
  inspect(is_tool_allowed(server, "delete_file"), content="false")
  inspect(is_tool_allowed(server, "write_file"), content="false")
}

///|
test "server config: decodes description field" {
  let text =
    #|{"mcpServers":{"github":{"transport":"http","url":"https://mcp.github.com/mcp","description":"GitHub Issues, PRs, and code search"}}}
  let config = decode_mcpx_config(@json.parse(text))
  let server = config.servers.get("github").unwrap()
  @debug.debug_inspect(
    server.description,
    content=(
      #|Some("GitHub Issues, PRs, and code search")
    ),
  )
}

///|
test "server config: missing description is None" {
  let text =
    #|{"mcpServers":{"github":{"transport":"http","url":"https://mcp.github.com/mcp"}}}
  let config = decode_mcpx_config(@json.parse(text))
  let server = config.servers.get("github").unwrap()
  @debug.debug_inspect(
    server.description,
    content=(
      #|None
    ),
  )
}

///|
test "server config: mcp_server_config forwards description" {
  let server = mcp_server_config(
    name="github",
    transport=ServerTransport::Http,
    url=Some("https://mcp.github.com/mcp"),
    description=Some("GitHub Issues and PRs"),
  )
  @debug.debug_inspect(
    server.description,
    content=(
      #|Some("GitHub Issues and PRs")
    ),
  )
}

///|
test "server config: glob matcher covers wildcard edge cases" {
  inspect(glob_match("*", ""), content="true")
  inspect(glob_match("*", "abc"), content="true")
  inspect(glob_match("read_*", "read_file"), content="true")
  inspect(glob_match("read_*", "write_file"), content="false")
  inspect(glob_match("a*b*c", "axbyc"), content="true")
  inspect(glob_match("a*b*c", "abc"), content="true")
  inspect(glob_match("a*b*c", "acb"), content="false")
  inspect(glob_match("foo?", "foox"), content="true")
  inspect(glob_match("foo?", "foo"), content="false")
  inspect(glob_match("*docs*", "query-docs"), content="true")
  inspect(glob_match("*a*a*a*a*b", "aaaaaaaaaaaaaaaaaac"), content="false")
  inspect(
    glob_match("*a*a*a*a*a*a*a*a*a*a*a*a*b", "aaaaaaaaaaaaaaaaaaaaaac"),
    content="false",
  )
  inspect(
    glob_match(
      "*a*a*a*a*a*a*a*a*a*a*a*a*a*a*a*a*a*a*a*a*b", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaac",
    ),
    content="false",
  )
}

///|
test "server config: auto keep-alive for known stdio commands unless dynamic chrome port" {
  let keep = mcp_server_config(
    name="browser",
    transport=ServerTransport::Stdio,
    command=Some("npx"),
    args=["-y", "@playwright/mcp"],
  )
  let dynamic_chrome = mcp_server_config(
    name="chrome-devtools",
    transport=ServerTransport::Stdio,
    command=Some("npx"),
    args=["chrome-devtools-mcp", "${CHROME_DEVTOOLS_URL}"],
  )
  @debug.debug_inspect(
    resolve_server_env(keep, Map([])),
    content=(
      #|Ok(
      #|  {
      #|    name: "browser",
      #|    transport: Stdio,
      #|    url: None,
      #|    command: Some("npx"),
      #|    args: ["-y", "@playwright/mcp"],
      #|    env: {},
      #|    cwd: None,
      #|    headers: {},
      #|    auth: None,
      #|    protocol_mode: None,
      #|    lifecycle: Some({ mode: KeepAlive, idle_timeout_ms: None }),
      #|    allowed_tools: [],
      #|    disabled_tools: [],
      #|    description: None,
      #|  },
      #|)

    ),
  )
  @debug.debug_inspect(
    resolve_server_env(dynamic_chrome, {
      "CHROME_DEVTOOLS_URL": "http://127.0.0.1:9222",
    }),
    content=(
      #|Ok(
      #|  {
      #|    name: "chrome-devtools",
      #|    transport: Stdio,
      #|    url: None,
      #|    command: Some("npx"),
      #|    args: ["chrome-devtools-mcp", "http://127.0.0.1:9222"],
      #|    env: {},
      #|    cwd: None,
      #|    headers: {},
      #|    auth: None,
      #|    protocol_mode: None,
      #|    lifecycle: Some({ mode: Ephemeral, idle_timeout_ms: None }),
      #|    allowed_tools: [],
      #|    disabled_tools: [],
      #|    description: None,
      #|  },
      #|)

    ),
  )
}

///|
test "server config: keep-alive env overrides by server or canonical name" {
  let server = mcp_server_config(
    name="custom",
    transport=ServerTransport::Stdio,
    command=Some("npx"),
    args=["@playwright/mcp"],
  )
  @debug.debug_inspect(
    resolve_server_env(server, { "MCPX_DISABLE_KEEPALIVE": "playwright" }),
    content=(
      #|Ok(
      #|  {
      #|    name: "custom",
      #|    transport: Stdio,
      #|    url: None,
      #|    command: Some("npx"),
      #|    args: ["@playwright/mcp"],
      #|    env: {},
      #|    cwd: None,
      #|    headers: {},
      #|    auth: None,
      #|    protocol_mode: None,
      #|    lifecycle: None,
      #|    allowed_tools: [],
      #|    disabled_tools: [],
      #|    description: None,
      #|  },
      #|)

    ),
  )
}
