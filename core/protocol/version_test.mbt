///|
test "protocol version: parses supported and unknown versions" {
  inspect(
    parse_mcp_protocol_version("2025-03-26") == V2025_03_26,
    content="true",
  )
  inspect(
    parse_mcp_protocol_version("2025-06-18") == V2025_06_18,
    content="true",
  )
  inspect(
    parse_mcp_protocol_version("2025-11-25") == V2025_11_25,
    content="true",
  )
  inspect(
    parse_mcp_protocol_version("2026-07-28") == V2026_07_28,
    content="true",
  )
  inspect(
    parse_mcp_protocol_version("future") == Unknown("future"),
    content="true",
  )
}

///|
test "protocol version: routes request family only by version" {
  inspect(mcp_protocol_family(V2025_03_26) == InitializeEra, content="true")
  inspect(mcp_protocol_family(V2025_06_18) == InitializeEra, content="true")
  inspect(mcp_protocol_family(V2025_11_25) == InitializeEra, content="true")
  inspect(mcp_protocol_family(V2026_07_28) == StatelessCore, content="true")
  inspect(mcp_protocol_family(Unknown("future")) == Unsupported, content="true")
}

///|
test "protocol version: selects newest implemented compatible version explicitly" {
  let advertised = [McpProtocolVersion::V2025_03_26, V2026_07_28, V2025_11_25]
  inspect(
    newest_compatible_mcp_protocol_version(
      advertised,
      allow_stateless_core=true,
    ) ==
    Some(V2026_07_28),
    content="true",
  )
  inspect(
    newest_compatible_mcp_protocol_version(
      advertised,
      allow_stateless_core=false,
    ) ==
    Some(V2025_11_25),
    content="true",
  )
}

///|
test "protocol version: converts supported and unknown versions to strings" {
  inspect(mcp_protocol_version_to_string(V2026_07_28), content="2026-07-28")
  inspect(mcp_protocol_version_to_string(Unknown("future")), content="future")
}
