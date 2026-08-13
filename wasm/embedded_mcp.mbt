///|
fn run_mcp_http_initialize(obj : Map[String, Json]) -> String {
  let url = expect_string_field(obj, "url") catch {
    _ => return wasm_error("invalid_input", "url is required")
  }
  let client = @mcp_client.mcp_client(
    client_name="mcpx",
    client_version=@mcp_client.MCPX_CLIENT_VERSION,
  )
  let request = client.initialize_request()
  let request_id = request.expected_id() catch {
    _ => return wasm_error("invalid_state", "request id is required")
  }
  let state = Map([])
  state["phase"] = Json::string("mcp_http_initialize")
  state["url"] = Json::string(url)
  state["requestId"] = json_int(request_id)
  needs_host(Json::object(state), [
    @host.host_http_request(
      http_method="POST",
      url~,
      headers=mcp_http_headers(),
      body=Some(request.message.stringify()),
    ),
  ])
}

///|
fn run_mcp_http_operation(
  obj : Map[String, Json],
  operation~ : String,
) -> String {
  let url = expect_string_field(obj, "url") catch {
    _ => return wasm_error("invalid_input", "url is required")
  }
  let client = @mcp_client.mcp_client(
    client_name="mcpx",
    client_version=@mcp_client.MCPX_CLIENT_VERSION,
  )
  let request = client.initialize_request()
  let request_id = request.expected_id() catch {
    _ => return wasm_error("invalid_state", "request id is required")
  }
  let state = Map([])
  state["phase"] = Json::string("mcp_http_initialize")
  state["url"] = Json::string(url)
  state["requestId"] = json_int(request_id)
  state["operation"] = Json::string(operation)
  if operation == "call" {
    let tool_name = expect_string_field(obj, "toolName") catch {
      _ => return wasm_error("invalid_input", "toolName is required")
    }
    state["toolName"] = Json::string(tool_name)
    state["arguments"] = obj.get("arguments").unwrap_or(Json::empty_object())
  }
  needs_host(Json::object(state), [
    @host.host_http_request(
      http_method="POST",
      url~,
      headers=mcp_http_headers(),
      body=Some(request.message.stringify()),
    ),
  ])
}

///|
fn reduce_mcp_http_initialize(
  state_obj : Map[String, Json],
  host_result_json : String,
) -> String {
  let url = expect_string_field(state_obj, "url") catch {
    _ => return wasm_error("invalid_state", "url is required")
  }
  let request_id = expect_int_field(state_obj, "requestId") catch {
    _ => return wasm_error("invalid_state", "requestId is required")
  }
  let host_result_obj = parse_host_result(host_result_json) catch {
    _ => return wasm_error("invalid_host_result", "host result must be object")
  }
  let ok = expect_bool_field(host_result_obj, "ok") catch {
    _ => return wasm_error("invalid_host_result", "ok is required")
  }
  guard ok else {
    return wasm_error("mcp_transport_error", "initialize request failed")
  }
  let status_code = expect_int_field(host_result_obj, "statusCode") catch {
    _ => return wasm_error("invalid_host_result", "statusCode is required")
  }
  let content_type = optional_string_field(host_result_obj, "contentType")
  let body = expect_string_field(host_result_obj, "body") catch {
    _ => return wasm_error("invalid_host_result", "body is required")
  }
  let payload = match
    @mcp_client.decode_mcp_transport_payload(
      @mcp_client.mcp_transport_response(status_code~, content_type~, body~),
    ) {
    Ok(value) => value
    Err(_) => return wasm_error("mcp_protocol_error", "invalid response")
  }
  let response = @mcp_client.expect_json_payload(payload) catch {
    _ => return wasm_error("mcp_protocol_error", "expected json response")
  }
  match
    @mcp_client.decode_mcp_initialize_response(response, expected_id=request_id) {
    Ok(_) => ()
    Err(_) =>
      return wasm_error("mcp_protocol_error", "invalid initialize response")
  }
  let state = Map([])
  state["phase"] = Json::string("mcp_http_initialized")
  state["url"] = Json::string(url)
  copy_optional_fields(source=state_obj, target=state, fields=[
    "operation", "toolName", "arguments",
  ])
  needs_host(Json::object(state), [
    @host.host_http_request(
      http_method="POST",
      url~,
      headers=mcp_http_headers(),
      body=Some(@mcp_client.mcp_initialized_notification().stringify()),
    ),
  ])
}

///|
fn reduce_mcp_http_initialized(
  state_obj : Map[String, Json],
  host_result_json : String,
) -> String {
  let url = expect_string_field(state_obj, "url") catch {
    _ => return wasm_error("invalid_state", "url is required")
  }
  let host_result_obj = parse_host_result(host_result_json) catch {
    _ => return wasm_error("invalid_host_result", "host result must be object")
  }
  let ok = expect_bool_field(host_result_obj, "ok") catch {
    _ => return wasm_error("invalid_host_result", "ok is required")
  }
  guard ok else {
    return wasm_error("mcp_transport_error", "initialized notification failed")
  }
  match optional_string_field(state_obj, "operation") {
    Some("list") => {
      let client = @mcp_client.mcp_client(
        client_name="mcpx",
        client_version=@mcp_client.MCPX_CLIENT_VERSION,
      )
      ignore(client.initialize_request())
      let request = client.tools_list_request()
      let request_id = request.expected_id() catch {
        _ => return wasm_error("invalid_state", "request id is required")
      }
      let state = Map([])
      state["phase"] = Json::string("mcp_http_list")
      state["url"] = Json::string(url)
      state["requestId"] = json_int(request_id)
      needs_host(Json::object(state), [
        @host.host_http_request(
          http_method="POST",
          url~,
          headers=mcp_http_headers(),
          body=Some(request.message.stringify()),
        ),
      ])
    }
    Some("call") => {
      let tool_name = expect_string_field(state_obj, "toolName") catch {
        _ => return wasm_error("invalid_state", "toolName is required")
      }
      let arguments = state_obj.get("arguments").unwrap_or(Json::empty_object())
      let client = @mcp_client.mcp_client(
        client_name="mcpx",
        client_version=@mcp_client.MCPX_CLIENT_VERSION,
      )
      ignore(client.initialize_request())
      let request = client.tool_call_request(name=tool_name, arguments~)
      let request_id = request.expected_id() catch {
        _ => return wasm_error("invalid_state", "request id is required")
      }
      let state = Map([])
      state["phase"] = Json::string("mcp_http_call")
      state["url"] = Json::string(url)
      state["requestId"] = json_int(request_id)
      needs_host(Json::object(state), [
        @host.host_http_request(
          http_method="POST",
          url~,
          headers=mcp_http_headers(),
          body=Some(request.message.stringify()),
        ),
      ])
    }
    _ => {
      let obj = Map([])
      obj["status"] = Json::string("ready")
      obj["initialized"] = Json::boolean(true)
      Json::object(obj).stringify()
    }
  }
}

///|
fn reduce_mcp_http_list(
  state_obj : Map[String, Json],
  host_result_json : String,
) -> String {
  let request_id = expect_int_field(state_obj, "requestId") catch {
    _ => return wasm_error("invalid_state", "requestId is required")
  }
  let response = mcp_host_result_json(host_result_json) catch {
    _ => return wasm_error("mcp_protocol_error", "invalid response")
  }
  let tools = match
    @mcp_client.decode_mcp_tool_list_response(response, expected_id=request_id) {
    Ok(value) => value
    Err(_) => return wasm_error("mcp_protocol_error", "invalid list response")
  }
  let obj = Map([])
  obj["status"] = Json::string("ready")
  obj["tools"] = Json::array(tools.map(tool_info_json))
  Json::object(obj).stringify()
}

///|
fn reduce_mcp_http_call(
  state_obj : Map[String, Json],
  host_result_json : String,
) -> String {
  let request_id = expect_int_field(state_obj, "requestId") catch {
    _ => return wasm_error("invalid_state", "requestId is required")
  }
  let response = mcp_host_result_json(host_result_json) catch {
    _ => return wasm_error("mcp_protocol_error", "invalid response")
  }
  let result = @mcp_client.decode_mcp_result(response, expected_id=request_id) catch {
    _ => return wasm_error("mcp_protocol_error", "invalid call response")
  }
  let obj = Map([])
  obj["status"] = Json::string("ready")
  obj["result"] = result
  Json::object(obj).stringify()
}
