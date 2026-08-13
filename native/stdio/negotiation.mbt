///|
priv enum StdioProbeOutcome {
  Modern
  ModernError(String)
  ExplicitLegacy
  TimedOut
}

///|
async fn probe_modern_stdio(
  conn : StdioConnection,
) -> StdioProbeOutcome raise McpStdioError {
  let context = @mcp_client.mcp_request_context(
    protocol=V2026_07_28,
    client_name=@mcp_client.MCPX_CLIENT_NAME,
    client_version=@mcp_client.MCPX_CLIENT_VERSION,
  )
  write_json_line(conn, @mcp_client.mcp_discover_request(id=1, context))
  let response = read_response_for_id(conn, expected_id=1)
  match @mcp_client.decode_mcp_discover_response(response, expected_id=1) {
    Ok(discover) =>
      if discover.protocol_versions.contains(V2026_07_28) {
        Modern
      } else {
        ModernError("MCP 2026-07-28 is not supported")
      }
    Err(RemoteError(code, message)) =>
      classify_stdio_discovery_remote_error(code, message)
    Err(UnsupportedProtocolVersion(_, supported)) =>
      ModernError(
        "unsupported MCP protocol version; supported: " + supported.join(", "),
      )
    Err(HeaderMismatch(message)) =>
      ModernError("MCP header mismatch: " + message)
    Err(MissingRequiredClientCapability(message)) =>
      ModernError("missing required client capability: " + message)
    Err(InvalidResponse(message)) =>
      ModernError("invalid MCP discovery response: " + message)
  }
}

///|
fn classify_stdio_discovery_remote_error(
  code : Int,
  message : String,
) -> StdioProbeOutcome {
  if code == -32601 {
    ExplicitLegacy
  } else {
    ModernError(
      "modern MCP discovery error " + code.to_string() + ": " + message,
    )
  }
}
