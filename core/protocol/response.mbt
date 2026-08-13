///|
pub(all) enum McpResultType {
  Complete
  InputRequired
  Extension(String)
} derive(Debug, Eq)

///|
pub(all) enum McpCacheScope {
  Public
  Private
} derive(Debug, Eq)

///|
pub struct McpToolListPage {
  result_type : McpResultType
  tools : Array[McpToolInfo]
  next_cursor : String?
  ttl_ms : Int
  cache_scope : McpCacheScope
} derive(Debug)

///|
pub struct McpInitializeInfo {
  protocol_version : String
  server_name : String?
  server_version : String?
  capabilities : Json
} derive(Debug)

///|
pub fn decode_mcp_initialize_response(
  response : Json,
  expected_id~ : Int,
) -> Result[McpInitializeInfo, McpProtocolError] {
  let result = decode_mcp_result(response, expected_id~) catch {
    error => return Err(error)
  }
  match result {
    Object(obj) => {
      let protocol_version = match obj.get("protocolVersion") {
        Some(String(value)) => value
        _ =>
          return Err(
            McpProtocolError::InvalidResponse(
              "initialize result missing protocolVersion",
            ),
          )
      }
      let capabilities = obj.get("capabilities").unwrap_or(Json::empty_object())
      let (server_name, server_version) = decode_server_info(
        obj.get("serverInfo"),
      )
      Ok({ protocol_version, server_name, server_version, capabilities })
    }
    _ =>
      Err(McpProtocolError::InvalidResponse("initialize result must be object"))
  }
}

///|
pub fn decode_mcp_tool_list_response(
  response : Json,
  expected_id~ : Int,
) -> Result[Array[McpToolInfo], McpProtocolError] {
  match
    decode_mcp_tool_list_page(response, expected_id~, require_result_type=false) {
    Ok(page) => Ok(page.tools)
    Err(error) => Err(error)
  }
}

///|
pub fn decode_mcp_tool_list_page(
  response : Json,
  expected_id~ : Int,
  require_result_type~ : Bool,
) -> Result[McpToolListPage, McpProtocolError] {
  let result = decode_mcp_result(response, expected_id~) catch {
    error => return Err(error)
  }
  let obj = match result {
    Object(value) => value
    _ =>
      return Err(
        McpProtocolError::InvalidResponse("tools/list result must be object"),
      )
  }
  let result_type = match decode_result_type(obj.get("resultType")) {
    Some(McpResultType::Complete) => McpResultType::Complete
    Some(McpResultType::InputRequired) =>
      return Err(
        McpProtocolError::InvalidResponse(
          "tools/list resultType input_required is not complete",
        ),
      )
    Some(McpResultType::Extension(value)) =>
      return Err(
        McpProtocolError::InvalidResponse(
          "unsupported tools/list resultType: " + value,
        ),
      )
    None =>
      if require_result_type {
        return Err(
          McpProtocolError::InvalidResponse(
            "tools/list result missing resultType",
          ),
        )
      } else {
        McpResultType::Complete
      }
  }
  let tools_json = match obj.get("tools") {
    Some(Array(value)) => value
    _ =>
      return Err(
        McpProtocolError::InvalidResponse("tools/list result missing tools"),
      )
  }
  let tools = []
  for tool in tools_json {
    match decode_mcp_tool(tool) {
      Ok(value) => tools.push(value)
      Err(error) => return Err(error)
    }
  }
  let next_cursor = match obj.get("nextCursor") {
    Some(String(value)) => Some(value)
    Some(_) =>
      return Err(
        McpProtocolError::InvalidResponse(
          "tools/list nextCursor must be string",
        ),
      )
    None => None
  }
  let ttl_ms = match obj.get("ttlMs") {
    Some(Number(value, ..)) if value.trunc() == value && value >= 0.0 =>
      value.to_int()
    _ => 0
  }
  let cache_scope = match obj.get("cacheScope") {
    Some(String("public")) => McpCacheScope::Public
    _ => McpCacheScope::Private
  }
  Ok({ result_type, tools, next_cursor, ttl_ms, cache_scope })
}

///|
fn decode_result_type(value : Json?) -> McpResultType? {
  match value {
    Some(String("complete")) => Some(McpResultType::Complete)
    Some(String("input_required")) => Some(McpResultType::InputRequired)
    Some(String(other)) => Some(McpResultType::Extension(other))
    _ => None
  }
}

///|
pub fn decode_mcp_complete_result(
  response : Json,
  expected_id~ : Int,
  require_result_type? : Bool = false,
) -> Result[Json, McpProtocolError] {
  let result = decode_mcp_result(response, expected_id~) catch {
    error => return Err(error)
  }
  let result_type = match result {
    Object(obj) => decode_result_type(obj.get("resultType"))
    _ => None
  }
  match result_type {
    None if require_result_type =>
      Err(McpProtocolError::InvalidResponse("result missing resultType"))
    None | Some(McpResultType::Complete) => Ok(result)
    Some(McpResultType::InputRequired) =>
      Err(
        McpProtocolError::InvalidResponse(
          "resultType input_required is not supported",
        ),
      )
    Some(McpResultType::Extension(value)) =>
      Err(McpProtocolError::InvalidResponse("unsupported resultType: " + value))
  }
}

///|
pub fn decode_mcp_result(
  response : Json,
  expected_id~ : Int,
) -> Json raise McpProtocolError {
  let obj = match response {
    Object(value) => value
    _ => raise McpProtocolError::InvalidResponse("response must be object")
  }
  if obj.get("jsonrpc") != Some(Json::string("2.0")) {
    raise McpProtocolError::InvalidResponse("response jsonrpc must be 2.0")
  }
  match decode_response_id(obj.get("id")) {
    Some(id) if id == expected_id => ()
    _ => raise McpProtocolError::InvalidResponse("unexpected response id")
  }
  match (obj.get("result"), obj.get("error")) {
    (Some(_), Some(_)) =>
      raise McpProtocolError::InvalidResponse(
        "response must not contain both result and error",
      )
    (Some(result), None) => result
    (None, Some(error)) => raise decode_mcp_error(error)
    _ =>
      raise McpProtocolError::InvalidResponse("response missing result/error")
  }
}

///|
pub fn mcp_response_id(message : Json) -> Int? {
  match message {
    Object(obj) => decode_response_id(obj.get("id"))
    _ => None
  }
}

///|
fn decode_mcp_tool(json : Json) -> Result[McpToolInfo, McpProtocolError] {
  let obj = match json {
    Object(value) => value
    _ => return Err(McpProtocolError::InvalidResponse("tool must be object"))
  }
  let name = match obj.get("name") {
    Some(String(value)) => value
    _ =>
      return Err(McpProtocolError::InvalidResponse("tool.name must be string"))
  }
  let description = match obj.get("description") {
    Some(String(value)) => Some(value)
    Some(_) =>
      return Err(
        McpProtocolError::InvalidResponse("tool.description must be string"),
      )
    None => None
  }
  let input_schema = match obj.get("inputSchema") {
    Some(Object(_) as value) => value
    _ =>
      return Err(
        McpProtocolError::InvalidResponse("tool.inputSchema must be object"),
      )
  }
  let output_schema = match obj.get("outputSchema") {
    Some(Object(_) as value) => Some(value)
    Some(_) =>
      return Err(
        McpProtocolError::InvalidResponse("tool.outputSchema must be object"),
      )
    None => None
  }
  Ok({ name, description, input_schema, output_schema })
}

///|
fn decode_server_info(json : Json?) -> (String?, String?) {
  match json {
    Some(Object(obj)) => {
      let name = match obj.get("name") {
        Some(String(value)) => Some(value)
        _ => None
      }
      let version = match obj.get("version") {
        Some(String(value)) => Some(value)
        _ => None
      }
      (name, version)
    }
    _ => (None, None)
  }
}

///|
fn decode_response_id(json : Json?) -> Int? {
  match json {
    Some(Number(value, ..)) if value.trunc() == value => Some(value.to_int())
    _ => None
  }
}

///|
fn decode_mcp_error(json : Json) -> McpProtocolError {
  match json {
    Object(obj) => {
      let code = match obj.get("code") {
        Some(Number(value, ..)) if value.trunc() == value => value.to_int()
        _ =>
          return McpProtocolError::InvalidResponse(
            "JSON-RPC error code must be an integer",
          )
      }
      let message = match obj.get("message") {
        Some(String(value)) => value
        _ =>
          return McpProtocolError::InvalidResponse(
            "JSON-RPC error message must be a string",
          )
      }
      match code {
        -32020 => McpProtocolError::HeaderMismatch(message)
        -32021 => McpProtocolError::MissingRequiredClientCapability(message)
        -32022 => {
          let (requested, supported) = decode_unsupported_version_data(
            obj.get("data"),
          )
          McpProtocolError::UnsupportedProtocolVersion(requested, supported)
        }
        _ => McpProtocolError::RemoteError(code, message)
      }
    }
    _ => McpProtocolError::InvalidResponse("JSON-RPC error must be an object")
  }
}

///|
fn decode_unsupported_version_data(data : Json?) -> (String?, Array[String]) {
  match data {
    Some(Object(obj)) => {
      let requested = match obj.get("requested") {
        Some(String(value)) => Some(value)
        _ => None
      }
      let supported = []
      match obj.get("supported") {
        Some(Array(values)) =>
          for value in values {
            match value {
              String(version) => supported.push(version)
              _ => ()
            }
          }
        _ => ()
      }
      (requested, supported)
    }
    _ => (None, [])
  }
}
