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
    protocol=@mcp_client.McpProtocolVersion::V2026_07_28,
    client_name=@mcp_client.MCPX_CLIENT_NAME,
    client_version=@mcp_client.MCPX_CLIENT_VERSION,
  )
  write_json_line(conn, @mcp_client.mcp_discover_request(id=1, context))
  let response = read_response_for_id(conn, expected_id=1)
  match @mcp_client.decode_mcp_discover_response(response, expected_id=1) {
    Ok(discover) =>
      if discover.protocol_versions.contains(
          @mcp_client.McpProtocolVersion::V2026_07_28,
        ) {
        StdioProbeOutcome::Modern
      } else {
        StdioProbeOutcome::ModernError("MCP 2026-07-28 is not supported")
      }
    Err(@mcp_client.McpProtocolError::RemoteError(code, message)) =>
      classify_stdio_discovery_remote_error(code, message)
    Err(@mcp_client.McpProtocolError::UnsupportedProtocolVersion(_, supported)) =>
      StdioProbeOutcome::ModernError(
        "unsupported MCP protocol version; supported: " + supported.join(", "),
      )
    Err(@mcp_client.McpProtocolError::HeaderMismatch(message)) =>
      StdioProbeOutcome::ModernError("MCP header mismatch: " + message)
    Err(@mcp_client.McpProtocolError::MissingRequiredClientCapability(message)) =>
      StdioProbeOutcome::ModernError(
        "missing required client capability: " + message,
      )
    Err(@mcp_client.McpProtocolError::InvalidResponse(message)) =>
      StdioProbeOutcome::ModernError(
        "invalid MCP discovery response: " + message,
      )
  }
}

///|
fn classify_stdio_discovery_remote_error(
  code : Int,
  message : String,
) -> StdioProbeOutcome {
  if code == -32601 {
    StdioProbeOutcome::ExplicitLegacy
  } else {
    StdioProbeOutcome::ModernError(
      "modern MCP discovery error " + code.to_string() + ": " + message,
    )
  }
}
