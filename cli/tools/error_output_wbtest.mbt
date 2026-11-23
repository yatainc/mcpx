///|
test "MCP error details are not truncated" {
  let message = "あ".repeat(257)
  assert_eq(mcp_error_detail(message), message)
}

///|
async test "MCP JSON-RPC and HTTP errors have distinct messages" {
  let invalid_params =
    #|{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"Invalid params\n\u001b[31m"}}
  let cases = [
    (
      400, invalid_params, "Error: remote MCP JSON-RPC error (-32602): Invalid params\\n\\u{1b}[31m",
    ),
    (429, "{}", "Error: remote returned HTTP 429"),
  ]
  for (status_code, body, expected) in cases {
    try
      @core_http.list_tools(
        _ => @core_http.http_response(status_code~, body~),
        @core_http.http_endpoint(url="https://mcp.example"),
      )
    catch {
      error => assert_eq(mcp_http_error_result("remote", error), expected)
    } noraise {
      _ => fail("expected MCP request to fail")
    }
  }
}
