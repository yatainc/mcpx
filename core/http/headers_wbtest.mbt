///|
test "HTTP headers: set replaces every case variant" {
  let headers = {
    "Content-Type": "text/plain",
    "content-TYPE": "application/xml",
  }
  set_header_case_insensitive(headers, "content-type", "application/json")
  inspect(headers.length(), content="1")
  inspect(
    header(headers, "CONTENT-TYPE") == Some("application/json"),
    content="true",
  )
}

///|
test "HTTP headers: modern builder sanitizes reserved headers" {
  let headers = build_modern_headers(
    {
      "mcp-session-id": "injected",
      "Mcp-Method": "injected",
      "mcp-name": "injected",
      "MCP-PARAM-admin": "true",
      "Accept": "text/plain",
    },
    @protocol.McpProtocolVersion::V2026_07_28,
    "tools/call",
    Some("検索"),
  )
  inspect(header(headers, "mcp-session-id") is None, content="true")
  inspect(header(headers, "mcp-param-admin") is None, content="true")
  inspect(
    header(headers, "mcp-protocol-version") == Some("2026-07-28"),
    content="true",
  )
  inspect(header(headers, "mcp-method") == Some("tools/call"), content="true")
  inspect(
    header(headers, "mcp-name") == Some("=?base64?5qSc57Si?="),
    content="true",
  )
  inspect(
    header(headers, "accept") == Some("application/json, text/event-stream"),
    content="true",
  )
}

///|
test "HTTP headers: legacy builder accepts only server session state" {
  let headers = build_headers_legacy(
    {
      "MCP-Session-ID": "injected",
      "mcp-protocol-version": "injected",
      "mcp-param-region": "injected",
    },
    Some("server-session"),
  )
  inspect(
    header(headers, "mcp-session-id") == Some("server-session"),
    content="true",
  )
  inspect(header(headers, "mcp-protocol-version") is None, content="true")
  inspect(header(headers, "mcp-param-region") is None, content="true")
}
