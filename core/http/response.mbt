///|
fn response_json(
  response : HttpResponse,
  expected_id? : Int = 1,
) -> Json raise McpHttpClientError {
  payload_json(response_payload(response, expected_id~))
}

///|
fn response_payload(
  response : HttpResponse,
  expected_id? : Int = 1,
) -> @protocol.McpTransportPayload raise McpHttpClientError {
  if response.status_code != 200 && response.status_code != 202 {
    let json = @json.parse(response.body) catch {
      _ => raise McpHttpClientError::HttpStatus(response.status_code)
    }
    if jsonrpc_error_code(json) is None {
      raise McpHttpClientError::HttpStatus(response.status_code)
    }
    ignore(
      @protocol.decode_mcp_result(json, expected_id~) catch {
        error => raise protocol_error_to_http(error)
      },
    )
    raise McpHttpClientError::HttpStatus(response.status_code)
  }
  match
    @protocol.decode_mcp_transport_payload(
      @protocol.mcp_transport_response(
        status_code=response.status_code,
        content_type=response.content_type,
        body=response.body,
      ),
    ) {
    Ok(value) => value
    Err(error) => raise protocol_error_to_http(error)
  }
}

///|
fn payload_json(
  payload : @protocol.McpTransportPayload,
) -> Json raise McpHttpClientError {
  @protocol.expect_json_payload(payload) catch {
    error => raise protocol_error_to_http(error)
  }
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
fn protocol_error_to_http(
  error : @protocol.McpProtocolError,
) -> McpHttpClientError {
  match error {
    @protocol.McpProtocolError::HeaderMismatch(message) =>
      HeaderMismatch(message)
    @protocol.McpProtocolError::MissingRequiredClientCapability(message) =>
      MissingRequiredClientCapability(message)
    @protocol.McpProtocolError::UnsupportedProtocolVersion(_, supported) =>
      UnsupportedProtocolVersion(supported)
    @protocol.McpProtocolError::RemoteError(code, message) =>
      RemoteError(code, message)
    @protocol.McpProtocolError::InvalidResponse(message) => Protocol(message)
  }
}
