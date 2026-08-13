///|
test "protocol version: parses supported and unknown versions" {
  inspect(
    parse_mcp_protocol_version("2025-03-26") == McpProtocolVersion::V2025_03_26,
    content="true",
  )
  inspect(
    parse_mcp_protocol_version("2025-06-18") == McpProtocolVersion::V2025_06_18,
    content="true",
  )
  inspect(
    parse_mcp_protocol_version("2025-11-25") == McpProtocolVersion::V2025_11_25,
    content="true",
  )
  inspect(
    parse_mcp_protocol_version("2026-07-28") == McpProtocolVersion::V2026_07_28,
    content="true",
  )
  inspect(
    parse_mcp_protocol_version("future") ==
    McpProtocolVersion::Unknown("future"),
    content="true",
  )
}

///|
test "protocol version: routes request family only by version" {
  inspect(
    mcp_protocol_family(McpProtocolVersion::V2025_03_26) ==
    McpProtocolFamily::InitializeEra,
    content="true",
  )
  inspect(
    mcp_protocol_family(McpProtocolVersion::V2025_06_18) ==
    McpProtocolFamily::InitializeEra,
    content="true",
  )
  inspect(
    mcp_protocol_family(McpProtocolVersion::V2025_11_25) ==
    McpProtocolFamily::InitializeEra,
    content="true",
  )
  inspect(
    mcp_protocol_family(McpProtocolVersion::V2026_07_28) ==
    McpProtocolFamily::StatelessCore,
    content="true",
  )
  inspect(
    mcp_protocol_family(McpProtocolVersion::Unknown("future")) ==
    McpProtocolFamily::Unsupported,
    content="true",
  )
}

///|
test "protocol version: selects newest implemented compatible version explicitly" {
  let advertised = [
    McpProtocolVersion::V2025_03_26,
    McpProtocolVersion::V2026_07_28,
    McpProtocolVersion::V2025_11_25,
  ]
  inspect(
    newest_compatible_mcp_protocol_version(
      advertised,
      allow_stateless_core=true,
    ) ==
    Some(McpProtocolVersion::V2026_07_28),
    content="true",
  )
  inspect(
    newest_compatible_mcp_protocol_version(
      advertised,
      allow_stateless_core=false,
    ) ==
    Some(McpProtocolVersion::V2025_11_25),
    content="true",
  )
}

///|
test "protocol version: converts supported and unknown versions to strings" {
  inspect(
    mcp_protocol_version_to_string(McpProtocolVersion::V2026_07_28),
    content="2026-07-28",
  )
  inspect(
    mcp_protocol_version_to_string(McpProtocolVersion::Unknown("future")),
    content="future",
  )
}
