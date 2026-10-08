///|
test "MCP HTTP header values preserve safe ASCII" {
  for value in ["search", "us-west1", "hello world", "a\tb"] {
    inspect(encode_mcp_http_header_value(value), content=value)
  }
}

///|
test "MCP HTTP header values encode unsafe UTF-8" {
  inspect(encode_mcp_http_header_value("検索"), content="=?base64?5qSc57Si?=")
  inspect(
    encode_mcp_http_header_value("Hello, 世界"),
    content="=?base64?SGVsbG8sIOS4lueVjA==?=",
  )
}

///|
test "MCP HTTP header values encode whitespace controls and sentinels" {
  inspect(
    encode_mcp_http_header_value(" padded "),
    content="=?base64?IHBhZGRlZCA=?=",
  )
  inspect(
    encode_mcp_http_header_value("line1\nline2"),
    content="=?base64?bGluZTEKbGluZTI=?=",
  )
  inspect(
    encode_mcp_http_header_value("=?base64?literal?="),
    content="=?base64?PT9iYXNlNjQ/bGl0ZXJhbD89?=",
  )
}
