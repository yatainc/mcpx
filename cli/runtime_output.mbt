///|
fn mcp_http_error_result(
  server_name : String,
  error : @mcp_http.McpHttpError,
) -> String {
  match @mcp_http.mcp_http_status_code(error) {
    Some(status_code) =>
      match @auth.auth_required_hint(server_name~, status_code~) {
        Some(hint) => auth_hint_result(hint)
        None =>
          error_result(
            server_name + " " + mcp_http_skip_message(server_name, error),
          )
      }
    None =>
      error_result(
        server_name + " " + mcp_http_skip_message(server_name, error),
      )
  }
}

///|
fn mcp_http_skip_message(
  server_name : String,
  error : @mcp_http.McpHttpError,
) -> String {
  match @mcp_http.mcp_http_status_code(error) {
    Some(status_code) =>
      match @auth.auth_required_hint(server_name~, status_code~) {
        Some(hint) => hint.summary
        None => "returned HTTP " + status_code.to_string()
      }
    None =>
      match @mcp_http.mcp_http_negotiation_message(error) {
        Some(message) => "MCP negotiation error: " + message
        None =>
          if @mcp_http.mcp_http_is_protocol_error(error) {
            "MCP protocol error"
          } else {
            "mcp http error"
          }
      }
  }
}
