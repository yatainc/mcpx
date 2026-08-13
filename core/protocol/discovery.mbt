///|
pub struct McpResponseMeta {
  server_info : Json?
  raw : Json
} derive(Debug)

///|
pub struct McpDiscoverInfo {
  protocol_versions : Array[McpProtocolVersion]
  capabilities : Json
  instructions : String?
  response_meta : McpResponseMeta
  result_type : String
  ttl_ms : Int
  cache_scope : String
} derive(Debug)

///|
pub fn mcp_discover_request(id~ : Int, context : McpRequestContext) -> Json {
  mcp_request(
    id,
    "server/discover",
    Some(with_mcp_request_meta(Map([]), context)),
  )
}

///|
pub fn decode_mcp_discover_response(
  response : Json,
  expected_id~ : Int,
) -> Result[McpDiscoverInfo, McpProtocolError] {
  let result = decode_mcp_result(response, expected_id~) catch {
    error => return Err(error)
  }
  let result = match result {
    Object(value) => value
    _ => return Err(InvalidResponse("discover result must be object"))
  }
  let result_type = match result.get("resultType") {
    Some(String("complete")) => "complete"
    Some(String(value)) =>
      return Err(InvalidResponse("unsupported discover resultType: " + value))
    _ => return Err(InvalidResponse("discover result missing resultType"))
  }
  let versions_json = match result.get("supportedVersions") {
    Some(Array(value)) => value
    _ =>
      return Err(InvalidResponse("discover result missing supportedVersions"))
  }
  let versions = []
  for value in versions_json {
    match value {
      String(version) => versions.push(parse_mcp_protocol_version(version))
      _ =>
        return Err(InvalidResponse("discover supported version must be string"))
    }
  }
  if versions.is_empty() {
    return Err(InvalidResponse("discover supportedVersions must not be empty"))
  }
  let capabilities = result.get("capabilities").unwrap_or(Json::empty_object())
  let instructions = match result.get("instructions") {
    Some(String(value)) => Some(value)
    Some(_) =>
      return Err(InvalidResponse("discover instructions must be string"))
    None => None
  }
  let raw_meta = result.get("_meta").unwrap_or(Json::empty_object())
  let namespaced_server_info = match raw_meta {
    Object(meta) => meta.get("io.modelcontextprotocol/serverInfo")
    _ => None
  }
  // RC SDKs and deployed reference servers may still emit result.serverInfo.
  let server_info = match namespaced_server_info {
    Some(value) => Some(value)
    None => result.get("serverInfo")
  }
  // Cache hints do not affect protocol correctness. Ignore malformed or
  // extension values rather than rejecting an otherwise usable discovery.
  let ttl_ms = match result.get("ttlMs") {
    Some(Number(value, ..)) if value.trunc() == value && value >= 0.0 =>
      value.to_int()
    _ => 0
  }
  let cache_scope = match result.get("cacheScope") {
    Some(String("public")) => "public"
    _ => "private"
  }
  Ok({
    protocol_versions: versions,
    capabilities,
    instructions,
    response_meta: { server_info, raw: raw_meta },
    result_type,
    ttl_ms,
    cache_scope,
  })
}
