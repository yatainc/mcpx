///|
#derive(Debug)
pub(all) suberror McpProtocolError {
  InvalidResponse(String)
  HeaderMismatch(String)
  MissingRequiredClientCapability(String)
  UnsupportedProtocolVersion(String?, Array[String])
  RemoteError(Int32, String)
}

///|
pub extend McpProtocolError with Debug::{to_repr}

///|
const MCP_PROTOCOL_VERSION : String = "2026-07-28"

///|
pub const MCP_PROTOCOL_VERSION_LEGACY : String = "2025-11-25"

///|
pub fn mcp_initialize_request(
  id~ : Int32,
  client_name~ : String,
  client_version~ : String,
  protocol_version~ : String = MCP_PROTOCOL_VERSION,
) -> Json {
  mcp_request(
    id,
    "initialize",
    Some({
      "protocolVersion": Json(protocol_version),
      "capabilities": {},
      "clientInfo": {
        "name": Json(client_name),
        "version": Json(client_version),
      },
    }),
  )
}

///|
pub fn mcp_initialized_notification() -> Json {
  mcp_notification("notifications/initialized", None)
}

///|
pub fn mcp_request(id : Int32, rpc_method : String, params : Json?) -> Json {
  let obj : Map[String, Json] = {
    "jsonrpc": "2.0",
    "id": Json(id),
    "method": Json(rpc_method),
  }
  match params {
    Some(value) => obj["params"] = value
    None => ()
  }
  Json::object(obj)
}

///|
fn mcp_notification(rpc_method : String, params : Json?) -> Json {
  let obj : Map[String, Json] = { "jsonrpc": "2.0", "method": Json(rpc_method) }
  match params {
    Some(value) => obj["params"] = value
    None => ()
  }
  Json::object(obj)
}
