///|
pub(all) enum McpProtocolVersion {
  V2025_03_26
  V2025_06_18
  V2025_11_25
  V2026_07_28
  Unknown(String)
} derive(Debug, Eq)

///|
pub(all) enum McpProtocolFamily {
  InitializeEra
  StatelessCore
  Unsupported
} derive(Debug, Eq)

///|
pub fn parse_mcp_protocol_version(value : String) -> McpProtocolVersion {
  match value {
    "2025-03-26" => V2025_03_26
    "2025-06-18" => V2025_06_18
    "2025-11-25" => V2025_11_25
    "2026-07-28" => V2026_07_28
    other => Unknown(other)
  }
}

///|
pub fn mcp_protocol_version_to_string(version : McpProtocolVersion) -> String {
  match version {
    V2025_03_26 => "2025-03-26"
    V2025_06_18 => "2025-06-18"
    V2025_11_25 => "2025-11-25"
    V2026_07_28 => "2026-07-28"
    Unknown(value) => value
  }
}

///|
pub fn newest_compatible_mcp_protocol_version(
  advertised : Array[McpProtocolVersion],
  allow_stateless_core~ : Bool,
) -> McpProtocolVersion? {
  let preference = if allow_stateless_core {
    [V2026_07_28, V2025_11_25, V2025_06_18, V2025_03_26]
  } else {
    [V2025_11_25, V2025_06_18, V2025_03_26]
  }
  for candidate in preference {
    if advertised.contains(candidate) {
      return Some(candidate)
    }
  }
  None
}

///|
pub fn mcp_protocol_family(version : McpProtocolVersion) -> McpProtocolFamily {
  match version {
    V2025_03_26 | V2025_06_18 | V2025_11_25 => InitializeEra
    V2026_07_28 => StatelessCore
    Unknown(_) => Unsupported
  }
}
