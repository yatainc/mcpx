///|
test "mcp request: builds initialize and notification" {
  inspect(MCP_PROTOCOL_VERSION, content="2026-07-28")
  inspect(MCP_PROTOCOL_VERSION_LEGACY, content="2025-11-25")
  inspect(
    mcp_initialize_request(id=1, client_name="mcpx", client_version="0.1.3").stringify(),
    content=(
      #|{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2026-07-28","capabilities":{},"clientInfo":{"name":"mcpx","version":"0.1.3"}}}
    ),
  )
  inspect(
    mcp_initialize_request(
      id=1,
      client_name="mcpx",
      client_version="0.1.3",
      protocol_version="2025-03-26",
    ).stringify(),
    content=(
      #|{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"mcpx","version":"0.1.3"}}}
    ),
  )
  inspect(
    mcp_initialized_notification().stringify(),
    content="{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",
  )
}

///|
test "mcp request: encodes arbitrary methods without a feature wrapper" {
  json_inspect(
    mcp_request(7, "example/read", Some({ "uri": "custom://item" })),
    content={
      "jsonrpc": "2.0",
      "id": 7,
      "method": "example/read",
      "params": { "uri": "custom://item" },
    },
  )
  json_inspect(mcp_request(8, "example/ping", None), content={
    "jsonrpc": "2.0",
    "id": 8,
    "method": "example/ping",
  })
  json_inspect(
    mcp_notification("example/changed", Some({ "uri": "custom://item" })),
    content={
      "jsonrpc": "2.0",
      "method": "example/changed",
      "params": { "uri": "custom://item" },
    },
  )
}
