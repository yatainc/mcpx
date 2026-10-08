///|
pub(all) suberror McpProtocolError {
  InvalidResponse(String)
  HeaderMismatch(String)
  MissingRequiredClientCapability(String)
  UnsupportedProtocolVersion(String?, Array[String])
  RemoteError(Int, String)
} derive(Debug)

///|
const MCP_PROTOCOL_VERSION : String = "2026-07-28"

///|
pub const MCP_PROTOCOL_VERSION_LEGACY : String = "2025-11-25"

///|
pub fn mcp_initialize_request(
  id~ : Int,
  client_name~ : String,
  client_version~ : String,
  protocol_version? : String = MCP_PROTOCOL_VERSION,
) -> Json {
  mcp_request(
    id,
    "initialize",
    Some({
      "protocolVersion": protocol_version.to_json(),
      "capabilities": {},
      "clientInfo": {
        "name": client_name.to_json(),
        "version": client_version.to_json(),
      },
    }),
  )
}

///|
pub fn mcp_initialized_notification() -> Json {
  mcp_notification("notifications/initialized", None)
}

///|
pub fn mcp_request(id : Int, rpc_method : String, params : Json?) -> Json {
  let obj : Map[String, Json] = {
    "jsonrpc": "2.0",
    "id": id.to_json(),
    "method": rpc_method.to_json(),
  }
  match params {
    Some(value) => obj["params"] = value
    None => ()
  }
  Json::object(obj)
}

///|
fn mcp_notification(rpc_method : String, params : Json?) -> Json {
  let obj : Map[String, Json] = {
    "jsonrpc": "2.0",
    "method": rpc_method.to_json(),
  }
  match params {
    Some(value) => obj["params"] = value
    None => ()
  }
  Json::object(obj)
}
