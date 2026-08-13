///|
fn build_headers_legacy(
  base_headers : Map[String, String],
  session_id : String?,
) -> Map[String, String] {
  let headers = base_headers.copy()
  for
    key in ["Mcp-Session-Id", "MCP-Protocol-Version", "Mcp-Method", "Mcp-Name"] {
    remove_header_case_insensitive(headers, key)
  }
  remove_headers_with_prefix_case_insensitive(headers, "Mcp-Param-")
  set_header_case_insensitive(headers, "content-type", "application/json")
  set_header_case_insensitive(
    headers, "accept", "application/json, text/event-stream",
  )
  match session_id {
    Some(value) => set_header_case_insensitive(headers, "Mcp-Session-Id", value)
    None => ()
  }
  headers
}

///|
fn build_modern_headers(
  base_headers : Map[String, String],
  version : @protocol.McpProtocolVersion,
  rpc_method : String,
  rpc_name : String?,
) -> Map[String, String] {
  let headers = build_headers_legacy(base_headers, None)
  headers["MCP-Protocol-Version"] = @protocol.mcp_protocol_version_to_string(
    version,
  )
  headers["Mcp-Method"] = rpc_method
  match rpc_name {
    Some(value) => headers["Mcp-Name"] = encode_mcp_http_header_value(value)
    None => ()
  }
  headers
}

///|
fn set_header_case_insensitive(
  headers : Map[String, String],
  name : String,
  value : String,
) -> Unit {
  remove_header_case_insensitive(headers, name)
  headers[name] = value
}

///|
fn remove_header_case_insensitive(
  headers : Map[String, String],
  target : String,
) -> Unit {
  let removals = []
  for key, _ in headers {
    if key.equal_ignore_ascii_case(target) {
      removals.push(key)
    }
  }
  for key in removals {
    headers.remove(key)
  }
}

///|
fn remove_headers_with_prefix_case_insensitive(
  headers : Map[String, String],
  prefix : String,
) -> Unit {
  let normalized = prefix.to_lower()
  let removals = []
  for key, _ in headers {
    if key.to_lower().has_prefix(normalized) {
      removals.push(key)
    }
  }
  for key in removals {
    headers.remove(key)
  }
}

///|
fn header(headers : Map[String, String], key : String) -> String? {
  for name, value in headers {
    if name.equal_ignore_ascii_case(key) {
      return Some(value)
    }
  }
  None
}
