///|
fn response_json(response : HttpResponse, expected_id? : Int = 1) -> Json raise {
  expect_json(response_payload(response, expected_id~))
}

///|
fn response_payload(
  response : HttpResponse,
  expected_id? : Int = 1,
) -> Payload raise {
  if response.status_code != 200 && response.status_code != 202 {
    let json = @json.parse(response.body) catch {
      _ => raise HttpStatus(response.status_code)
    }
    if jsonrpc_error_code(json) is None {
      raise HttpStatus(response.status_code)
    }
    ignore(@protocol.decode_mcp_result(json, expected_id~))
    raise HttpStatus(response.status_code)
  }
  decode_payload(response)
}

///|
fn jsonrpc_error_code(json : Json) -> Int? {
  match json {
    Object(obj) =>
      match obj.get("error") {
        Some(Object(error)) =>
          match error.get("code") {
            Some(Number(value, ..)) => Some(value.to_int())
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn protocol_error_to_http(error : Error) -> McpHttpClientError {
  match error {
    @protocol.InvalidResponse(message) | Protocol(message) => Protocol(message)
    @protocol.HeaderMismatch(message) | HeaderMismatch(message) =>
      HeaderMismatch(message)
    @protocol.MissingRequiredClientCapability(message)
    | MissingRequiredClientCapability(message) =>
      MissingRequiredClientCapability(message)
    @protocol.UnsupportedProtocolVersion(_, supported)
    | UnsupportedProtocolVersion(supported) =>
      UnsupportedProtocolVersion(supported)
    @protocol.RemoteError(code, message) | RemoteError(code, message) =>
      RemoteError(code, message)
    HttpStatus(code) => HttpStatus(code)
    Network(message) => Network(message)
    ModeProtocolIncompatible(mode, protocol) =>
      ModeProtocolIncompatible(mode, protocol)
    _ => Network(error.to_string())
  }
}

///|
async fn[T] with_http_errors(
  operation : async () -> T,
) -> T raise McpHttpClientError {
  operation() catch {
    error => raise protocol_error_to_http(error)
  }
}
