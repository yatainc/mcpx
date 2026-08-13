///|
test "mcp client request: builds initialize notification and legacy tool requests" {
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
  inspect(
    mcp_tools_list_request_legacy(id=2).stringify(),
    content="{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{}}",
  )
  inspect(
    mcp_tool_call_request_legacy(
      id=3,
      name="search",
      arguments=Json::object({ "q": Json::string("moonbit") }),
    ).stringify(),
    content=(
      #|{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search","arguments":{"q":"moonbit"}}}
    ),
  )
}

///|
test "mcp client request: builds 2026 stateless tools requests" {
  inspect(
    mcp_tools_list_request(id=1, client_name="mcpx", client_version="0.1.3").stringify(),
    content=(
      #|{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"mcpx","version":"0.1.3"},"io.modelcontextprotocol/clientCapabilities":{}}}}
    ),
  )
  inspect(
    mcp_tool_call_request(
      id=1,
      name="search",
      arguments=Json::object({ "q": Json::string("moonbit") }),
      client_name="mcpx",
      client_version="0.1.3",
    ).stringify(),
    content=(
      #|{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search","arguments":{"q":"moonbit"},"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"mcpx","version":"0.1.3"},"io.modelcontextprotocol/clientCapabilities":{}}}}
    ),
  )
}
