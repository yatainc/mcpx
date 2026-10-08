///|
async fn list_tools_legacy(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  version : @protocol.McpProtocolVersion,
) -> Array[@tools.McpToolInfo] {
  let session_id = Ref(None)
  initialize_legacy(fetch, endpoint, version, session_id)
  let payload = send_json_legacy(
    fetch,
    endpoint,
    session_id,
    @protocol.mcp_request(2, "tools/list", Some(@tools.list_params().to_json())),
    expected_id=2,
  )
  let result = @protocol.decode_mcp_result(expect_json(payload), expected_id=2)
  @tools.decode_list_result(result).tools
}

///|
async fn call_tool_legacy(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  version : @protocol.McpProtocolVersion,
  tool_name~ : String,
  arguments~ : Json,
) -> Json {
  let session_id = Ref(None)
  initialize_legacy(fetch, endpoint, version, session_id)
  let payload = send_json_legacy(
    fetch,
    endpoint,
    session_id,
    @protocol.mcp_request(
      2,
      "tools/call",
      Some(@tools.call_params(tool_name, arguments).to_json()),
    ),
    expected_id=2,
  )
  @protocol.decode_mcp_result(expect_json(payload), expected_id=2)
}

///|
async fn initialize_legacy(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  version : @protocol.McpProtocolVersion,
  session_id : Ref[String?],
) -> Unit {
  let payload = send_json_legacy(
    fetch,
    endpoint,
    session_id,
    @protocol.mcp_initialize_request(
      id=1,
      client_name=@protocol.MCPX_CLIENT_NAME,
      client_version=@protocol.MCPX_CLIENT_VERSION,
      protocol_version=@protocol.mcp_protocol_version_to_string(version),
    ),
    expected_id=1,
  )
  ignore(
    @protocol.decode_mcp_initialize_result(
      @protocol.decode_mcp_result(expect_json(payload), expected_id=1),
    ),
  )
  ignore(
    send_json_legacy(
      fetch,
      endpoint,
      session_id,
      @protocol.mcp_initialized_notification(),
    ),
  )
}

///|
async fn send_json_legacy(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  session_id : Ref[String?],
  message : Json,
  expected_id? : Int = 1,
) -> Payload {
  let response = post_json(
    fetch,
    endpoint,
    build_headers_legacy(endpoint.headers, session_id.val),
    message,
  )
  match header(response.headers, "Mcp-Session-Id") {
    Some(value) => session_id.val = Some(value)
    None => ()
  }
  response_payload(response, expected_id~)
}
