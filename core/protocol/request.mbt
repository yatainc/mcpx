///|
pub struct McpToolInfo {
  name : String
  description : String?
  input_schema : Json
  output_schema : Json?
} derive(Debug)

///|
pub fn mcp_tool_info(
  name~ : String,
  description? : String? = None,
  input_schema~ : Json,
  output_schema? : Json? = None,
) -> McpToolInfo {
  { name, description, input_schema, output_schema }
}

///|
pub suberror McpProtocolError {
  InvalidResponse(String)
  HeaderMismatch(String)
  MissingRequiredClientCapability(String)
  UnsupportedProtocolVersion(String?, Array[String])
  RemoteError(Int, String)
} derive(Debug)

///|
pub const MCP_PROTOCOL_VERSION : String = MCP_PROTOCOL_VERSION_2026_07_28

///|
pub const MCP_PROTOCOL_VERSION_LEGACY : String = MCP_PROTOCOL_VERSION_2025_11_25

///|
pub fn mcp_initialize_request(
  id~ : Int,
  client_name~ : String,
  client_version~ : String,
  protocol_version? : String = MCP_PROTOCOL_VERSION,
) -> Json {
  let params = Map([])
  params["protocolVersion"] = Json::string(protocol_version)
  params["capabilities"] = Json::object(Map([]))
  let client_info = Map([])
  client_info["name"] = Json::string(client_name)
  client_info["version"] = Json::string(client_version)
  params["clientInfo"] = Json::object(client_info)
  mcp_request(id, "initialize", Some(Json::object(params)))
}

///|
pub fn mcp_initialized_notification() -> Json {
  mcp_notification("notifications/initialized", None)
}

///|
pub fn mcp_tools_list_request_legacy(id~ : Int) -> Json {
  mcp_request(id, "tools/list", Some(Json::object(Map([]))))
}

///|
pub fn mcp_tools_list_request(
  id~ : Int,
  client_name~ : String,
  client_version~ : String,
  cursor? : String? = None,
) -> Json {
  let params = Map([])
  match cursor {
    Some(value) => params["cursor"] = Json::string(value)
    None => ()
  }
  params["_meta"] = mcp_request_meta(
    mcp_request_context(
      protocol=McpProtocolVersion::V2026_07_28,
      client_name~,
      client_version~,
    ),
  )
  mcp_request(id, "tools/list", Some(Json::object(params)))
}

///|
pub fn mcp_tool_call_request_legacy(
  id~ : Int,
  name~ : String,
  arguments~ : Json,
) -> Json {
  let params = Map([])
  params["name"] = Json::string(name)
  params["arguments"] = arguments
  mcp_request(id, "tools/call", Some(Json::object(params)))
}

///|
pub fn mcp_tool_call_request(
  id~ : Int,
  name~ : String,
  arguments~ : Json,
  client_name~ : String,
  client_version~ : String,
) -> Json {
  let params = Map([])
  params["name"] = Json::string(name)
  params["arguments"] = arguments
  params["_meta"] = mcp_request_meta(
    mcp_request_context(
      protocol=McpProtocolVersion::V2026_07_28,
      client_name~,
      client_version~,
    ),
  )
  mcp_request(id, "tools/call", Some(Json::object(params)))
}

///|
pub fn mcp_request(id : Int, rpc_method : String, params : Json?) -> Json {
  let obj = Map([])
  obj["jsonrpc"] = Json::string("2.0")
  obj["id"] = json_int(id)
  obj["method"] = Json::string(rpc_method)
  match params {
    Some(value) => obj["params"] = value
    None => ()
  }
  Json::object(obj)
}

///|
pub fn mcp_notification(rpc_method : String, params : Json?) -> Json {
  let obj = Map([])
  obj["jsonrpc"] = Json::string("2.0")
  obj["method"] = Json::string(rpc_method)
  match params {
    Some(value) => obj["params"] = value
    None => ()
  }
  Json::object(obj)
}

///|
fn json_int(value : Int) -> Json {
  Json::number(Double::from_int(value), repr=value.to_string())
}
