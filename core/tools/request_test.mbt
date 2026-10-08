///|
test "tools request: builds legacy list and call parameters" {
  inspect(
    @protocol.mcp_request(2, "tools/list", Some(@tools.list_params().to_json())).stringify(),
    content="{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{}}",
  )
  inspect(
    @protocol.mcp_request(
      3,
      "tools/call",
      Some(@tools.call_params("search", { "q": "moonbit" }).to_json()),
    ).stringify(),
    content=(
      #|{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search","arguments":{"q":"moonbit"}}}
    ),
  )
}

///|
test "tools request: accepts transport metadata without owning a session" {
  let context = @protocol.mcp_request_context(
    protocol=V2026_07_28,
    client_name="mcpx",
    client_version="0.1.3",
  )
  inspect(
    @protocol.mcp_request(
      1,
      "tools/list",
      Some(@protocol.with_mcp_request_meta(@tools.list_params(), context)),
    ).stringify(),
    content=(
      #|{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"mcpx","version":"0.1.3"},"io.modelcontextprotocol/clientCapabilities":{}}}}
    ),
  )
  inspect(
    @protocol.mcp_request(
      1,
      "tools/call",
      Some(
        @protocol.with_mcp_request_meta(
          @tools.call_params("search", { "q": "moonbit" }),
          context,
        ),
      ),
    ).stringify(),
    content=(
      #|{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search","arguments":{"q":"moonbit"},"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"mcpx","version":"0.1.3"},"io.modelcontextprotocol/clientCapabilities":{}}}}
    ),
  )
}
