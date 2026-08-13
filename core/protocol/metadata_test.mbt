///|
test "protocol metadata: builds required 2026 request envelope" {
  let context = mcp_request_context(
    protocol=McpProtocolVersion::V2026_07_28,
    client_name="mcpx",
    client_version="0.1.4",
  )
  inspect(
    mcp_request_meta(context).stringify(),
    content=(
      #|{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"mcpx","version":"0.1.4"},"io.modelcontextprotocol/clientCapabilities":{}}
    ),
  )
}

///|
test "protocol metadata: inserts envelope without dropping request params" {
  let context = mcp_request_context(
    protocol=McpProtocolVersion::V2026_07_28,
    client_name="mcpx",
    client_version="0.1.4",
  )
  inspect(
    with_mcp_request_meta(
      { "name": Json::string("search") },
      context,
    ).stringify(),
    content=(
      #|{"name":"search","_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"mcpx","version":"0.1.4"},"io.modelcontextprotocol/clientCapabilities":{}}}
    ),
  )
}

///|
test "protocol metadata: preserves declared client capabilities" {
  let context = mcp_request_context(
    protocol=McpProtocolVersion::V2026_07_28,
    client_name="mcpx",
    client_version="0.1.4",
    client_capabilities={ "sampling": Json::empty_object() },
  )
  let meta = mcp_request_meta(context)
  inspect(
    meta.stringify().contains("\"sampling\":{}"),
    content="true",
  )
}
