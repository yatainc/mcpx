///|
fn error_result(message : String) -> String {
  "Error: " + message
}

///|
fn mcp_http_error_result(
  server_name : String,
  error : @core_http.McpHttpClientError,
) -> String {
  let message = match error {
    HttpStatus(status_code) =>
      match @auth.auth_required_hint(server_name~, status_code~) {
        Some(hint) => {
          let lines = ["Error: " + hint.summary]
          if !hint.suggested_commands.is_empty() {
            lines.push("")
            lines.push("Try:")
            for command in hint.suggested_commands {
              lines.push("  " + command)
            }
          }
          match hint.config_hint {
            Some(value) => {
              lines.push("")
              lines.push(value)
            }
            None => ()
          }
          return lines.join("\n")
        }
        None => "returned HTTP " + status_code.to_string()
      }
    Protocol(_) | RemoteError(_, _) => "MCP protocol error"
    HeaderMismatch(message) =>
      "MCP negotiation error: header mismatch: " + message
    MissingRequiredClientCapability(message) =>
      "MCP negotiation error: missing required client capability: " + message
    UnsupportedProtocolVersion(supported) =>
      "MCP negotiation error: unsupported MCP protocol version; supported: " +
      supported.join(", ")
    ModeProtocolIncompatible(mode, protocol) =>
      "MCP negotiation error: protocol mode " +
      mode +
      " is incompatible with MCP " +
      protocol
    Network(_) => "mcp http error"
  }
  error_result(server_name + " " + message)
}
