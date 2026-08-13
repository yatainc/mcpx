///|
test "server config encode: empty config" {
  inspect(
    empty_mcpx_config().to_json().stringify(),
    content="{\"mcpServers\":{}}",
  )
}

///|
test "server config encode: add remote URL server without forcing auth" {
  let config = put_remote_mcp_server(
    empty_mcpx_config(),
    name="github",
    url="https://mcp.github.com/mcp",
  )
  inspect(
    config.to_json().stringify(),
    content=(
      #|{"mcpServers":{"github":{"transport":"http","url":"https://mcp.github.com/mcp"}}}
    ),
  )
}

///|
test "server config encode: OAuth static client remains env-templated" {
  let config = put_server_config(
    empty_mcpx_config(),
    mcp_server_config(
      name="github",
      transport=Http,
      url=Some("https://mcp.github.com/mcp"),
      auth=Some(
        oauth_server_auth(
          client_id=Some("${GITHUB_CLIENT_ID}"),
          client_secret=Some("${GITHUB_CLIENT_SECRET}"),
        ),
      ),
    ),
  )
  inspect(
    config.to_json().stringify(),
    content=(
      #|{"mcpServers":{"github":{"transport":"http","url":"https://mcp.github.com/mcp","auth":{"type":"oauth","clientId":"${GITHUB_CLIENT_ID}","clientSecret":"${GITHUB_CLIENT_SECRET}"}}}}
    ),
  )
}

///|
test "server config encode: stdio env and cwd" {
  let config = put_server_config(
    empty_mcpx_config(),
    mcp_server_config(
      name="local",
      transport=Stdio,
      command=Some("node"),
      args=["server.js"],
      env={ "API_TOKEN": "${API_TOKEN}" },
      cwd=Some("/srv/mcp"),
    ),
  )
  inspect(
    config.to_json().stringify(),
    content=(
      #|{"mcpServers":{"local":{"transport":"stdio","command":"node","args":["server.js"],"env":{"API_TOKEN":"${API_TOKEN}"},"cwd":"/srv/mcp"}}}
    ),
  )
}

///|
test "server config encode: lifecycle keep-alive shorthand" {
  let config = put_server_config(
    empty_mcpx_config(),
    mcp_server_config(
      name="playwright",
      transport=Stdio,
      command=Some("npx"),
      args=["@playwright/mcp"],
      lifecycle=Some(server_lifecycle(KeepAlive)),
    ),
  )
  inspect(
    config.to_json().stringify(),
    content=(
      #|{"mcpServers":{"playwright":{"transport":"stdio","command":"npx","args":["@playwright/mcp"],"lifecycle":"keep-alive"}}}
    ),
  )
}

///|
test "server config encode: tool filters" {
  let config = put_server_config(
    empty_mcpx_config(),
    mcp_server_config(
      name="github",
      transport=Http,
      url=Some("https://mcp.github.com/mcp"),
      allowed_tools=["read_*", "list_*"],
      disabled_tools=["delete_*"],
    ),
  )
  inspect(
    config.to_json().stringify(),
    content=(
      #|{"mcpServers":{"github":{"transport":"http","url":"https://mcp.github.com/mcp","allowedTools":["read_*","list_*"],"disabledTools":["delete_*"]}}}
    ),
  )
}
