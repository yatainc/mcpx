///|
pub(all) enum McpCacheScope {
  Public
  Private
} derive(Debug, Eq)

///|
pub extend McpCacheScope with Debug::{to_repr}

///|
pub extend McpCacheScope with Eq::{not_equal, equal}

///|
pub struct McpInitializeInfo {
  protocol_version : String
  server_name : String?
  server_version : String?
  capabilities : Json
} derive(Debug)

///|
pub extend McpInitializeInfo with Debug::{to_repr}

///|
pub fn decode_mcp_initialize_result(
  result : Json,
) -> McpInitializeInfo raise McpProtocolError {
  let obj = match result {
    Object(value) => value
    _ => raise InvalidResponse("initialize result must be object")
  }
  let protocol_version = match obj.get("protocolVersion") {
    Some(String(value)) => value
    _ => raise InvalidResponse("initialize result missing protocolVersion")
  }
  let capabilities = obj.get("capabilities").unwrap_or(Json::empty_object())
  let (server_name, server_version) = match obj.get("serverInfo") {
    Some(Object(info)) => {
      let name = match info.get("name") {
        Some(String(value)) => Some(value)
        _ => None
      }
      let version = match info.get("version") {
        Some(String(value)) => Some(value)
        _ => None
      }
      (name, version)
    }
    _ => (None, None)
  }
  { protocol_version, server_name, server_version, capabilities, }
}

///|
pub fn require_complete_result(
  result : Json,
  required? : Bool = true,
  operation? : String = "",
) -> Unit raise McpProtocolError {
  let result_type = match result {
    Object(obj) => obj.get("resultType")
    _ => None
  }
  let prefix = if operation.is_empty() { "" } else { operation + " " }
  match result_type {
    Some(String("complete")) => ()
    Some(String("input_required")) =>
      raise InvalidResponse(
        prefix + "resultType input_required is not supported",
      )
    Some(String(value)) =>
      raise InvalidResponse("unsupported " + prefix + "resultType: " + value)
    _ if required => raise InvalidResponse(prefix + "result missing resultType")
    _ => ()
  }
}

///|
pub fn decode_mcp_result(
  response : Json,
  expected_id~ : Int,
) -> Json raise McpProtocolError {
  let obj = match response {
    Object(value) => value
    _ => raise InvalidResponse("response must be object")
  }
  if obj.get("jsonrpc") != Some(Json::string("2.0")) {
    raise InvalidResponse("response jsonrpc must be 2.0")
  }
  match decode_response_id(obj.get("id")) {
    Some(id) if id == expected_id => ()
    _ => raise InvalidResponse("unexpected response id")
  }
  match (obj.get("result"), obj.get("error")) {
    (Some(_), Some(_)) =>
      raise InvalidResponse("response must not contain both result and error")
    (Some(result), None) => result
    (None, Some(error)) => raise decode_mcp_error(error)
    _ => raise InvalidResponse("response missing result/error")
  }
}

///|
fn decode_response_id(json : Json?) -> Int? {
  match json {
    Some(Number(value, ..)) if value.trunc() == value &&
      value >= -2147483648.0 &&
      value <= 2147483647.0 => Some(value.to_int())
    _ => None
  }
}

///|
fn decode_mcp_error(json : Json) -> McpProtocolError {
  match json {
    Object(obj) => {
      let code = match decode_response_id(obj.get("code")) {
        Some(value) => value
        None => return InvalidResponse("JSON-RPC error code must be an integer")
      }
      let message = match obj.get("message") {
        Some(String(value)) => value
        _ => return InvalidResponse("JSON-RPC error message must be a string")
      }
      match code {
        -32020 => HeaderMismatch(message)
        -32021 => MissingRequiredClientCapability(message)
        -32022 => {
          let (requested, supported) = decode_unsupported_version_data(
            obj.get("data"),
          )
          UnsupportedProtocolVersion(requested, supported)
        }
        _ => RemoteError(code, message)
      }
    }
    _ => InvalidResponse("JSON-RPC error must be an object")
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
      let supported = match obj.get("supported") {
        Some(Array(values)) =>
          values.filter_map(value => {
            match value {
              String(version) => Some(version)
              _ => None
            }
          })
        _ => []
      }
      (requested, supported)
    }
    _ => (None, [])
  }
}
