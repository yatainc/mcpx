///|
async fn list_tools_legacy(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  version : @protocol.McpProtocolVersion,
) -> Array[@protocol.McpToolInfo] raise McpHttpClientError {
  let session_id = Ref(None)
  let client = @protocol.mcp_client(
    client_name=@protocol.MCPX_CLIENT_NAME,
    client_version=@protocol.MCPX_CLIENT_VERSION,
    protocol_version=@protocol.mcp_protocol_version_to_string(version),
  )
  initialize_legacy(fetch, endpoint, client, session_id)
  let list = client.tools_list_request()
  let payload = send_json_legacy(fetch, endpoint, session_id, list.message)
  client.accept_tools_list_response(list, payload_json(payload)) catch {
    error => raise McpHttpClientError::Protocol(error.to_string())
  }
}

///|
async fn call_tool_legacy(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  version : @protocol.McpProtocolVersion,
  tool_name~ : String,
  arguments~ : Json,
) -> Json raise McpHttpClientError {
  let session_id = Ref(None)
  let client = @protocol.mcp_client(
    client_name=@protocol.MCPX_CLIENT_NAME,
    client_version=@protocol.MCPX_CLIENT_VERSION,
    protocol_version=@protocol.mcp_protocol_version_to_string(version),
  )
  initialize_legacy(fetch, endpoint, client, session_id)
  let call = client.tool_call_request(name=tool_name, arguments~)
  let payload = send_json_legacy(fetch, endpoint, session_id, call.message)
  client.accept_tool_call_response(call, payload_json(payload)) catch {
    error => raise McpHttpClientError::Protocol(error.to_string())
  }
}

///|
async fn initialize_legacy(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  client : @protocol.McpClient,
  session_id : Ref[String?],
) -> Unit raise McpHttpClientError {
  let init = client.initialize_request()
  let payload = send_json_legacy(fetch, endpoint, session_id, init.message)
  ignore(
    client.accept_initialize_response(init, payload_json(payload)) catch {
      error => raise McpHttpClientError::Protocol(error.to_string())
    },
  )
  let initialized = client.initialized_notification()
  ignore(send_json_legacy(fetch, endpoint, session_id, initialized.message))
}

///|
async fn send_json_legacy(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  session_id : Ref[String?],
  message : Json,
) -> @protocol.McpTransportPayload raise McpHttpClientError {
  let retain_session = endpoint.mode != @config.McpConnectionMode::Stateless
  let active_session = if retain_session { session_id.val } else { None }
  let response = post_json(
    fetch,
    endpoint,
    build_headers_legacy(endpoint.headers, active_session),
    message,
  )
  if retain_session {
    update_session_id(session_id, response.headers)
  }
  response_payload(response)
}

///|
fn update_session_id(
  session_id : Ref[String?],
  headers : Map[String, String],
) -> Unit {
  match header(headers, "Mcp-Session-Id") {
    Some(value) => session_id.val = Some(value)
    None => ()
  }
}
