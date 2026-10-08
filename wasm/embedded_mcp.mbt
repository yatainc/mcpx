///|
fn run_mcp_http_initialize(obj : Map[String, Json]) -> String {
  run_mcp_http_operation(obj, operation="initialize")
}

///|
fn run_mcp_http_operation(
  obj : Map[String, Json],
  operation~ : String,
) -> String {
  let url = expect_string_field(obj, "url") catch {
    _ => return wasm_error("invalid_input", "url is required")
  }
  let request = @protocol.mcp_initialize_request(
    id=1,
    client_name="mcpx",
    client_version=@protocol.MCPX_CLIENT_VERSION,
  )
  let state : Map[String, Json] = {
    "phase": "mcp_http_initialize",
    "url": url.to_json(),
    "requestId": 1,
  }
  if operation != "initialize" {
    state["operation"] = operation.to_json()
  }
  if operation == "call" {
    let tool_name = expect_string_field(obj, "toolName") catch {
      _ => return wasm_error("invalid_input", "toolName is required")
    }
    state["toolName"] = tool_name.to_json()
    state["arguments"] = obj.get("arguments").unwrap_or(Json::empty_object())
  }
  needs_host(Json::object(state), [
    @host.host_http_request(
      http_method="POST",
      url~,
      headers=mcp_http_headers(),
      body=Some(request.stringify()),
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
  let payload = @http.decode_payload(
    @http.http_response(status_code~, content_type~, body~),
  ) catch {
    _ => return wasm_error("mcp_protocol_error", "invalid response")
  }
  let response = @http.expect_json(payload) catch {
    _ => return wasm_error("mcp_protocol_error", "expected json response")
  }
  ignore(
    @protocol.decode_mcp_initialize_result(
      @protocol.decode_mcp_result(response, expected_id=request_id),
    ) catch {
      _ =>
        return wasm_error("mcp_protocol_error", "invalid initialize response")
    },
  )
  let state : Map[String, Json] = {
    "phase": "mcp_http_initialized",
    "url": url.to_json(),
  }
  copy_optional_fields(source=state_obj, target=state, fields=[
    "operation", "toolName", "arguments",
  ])
  needs_host(Json::object(state), [
    @host.host_http_request(
      http_method="POST",
      url~,
      headers=mcp_http_headers(),
      body=Some(@protocol.mcp_initialized_notification().stringify()),
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
  let (phase, rpc_method, params) = match
    optional_string_field(state_obj, "operation") {
    Some("list") => ("mcp_http_list", "tools/list", @tools.list_params())
    Some("call") => {
      let tool_name = expect_string_field(state_obj, "toolName") catch {
        _ => return wasm_error("invalid_state", "toolName is required")
      }
      let arguments = state_obj.get("arguments").unwrap_or(Json::empty_object())
      ("mcp_http_call", "tools/call", @tools.call_params(tool_name, arguments))
    }
    _ =>
      return Json::object({ "status": "ready", "initialized": true }).stringify()
  }
  let request = @protocol.mcp_request(2, rpc_method, Some(params.to_json()))
  needs_host(
    { "phase": phase.to_json(), "url": url.to_json(), "requestId": 2 },
    [
      @host.host_http_request(
        http_method="POST",
        url~,
        headers=mcp_http_headers(),
        body=Some(request.stringify()),
      ),
    ],
  )
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
  let tools = @tools.decode_list_result(
      @protocol.decode_mcp_result(response, expected_id=request_id),
    ).tools catch {
      _ => return wasm_error("mcp_protocol_error", "invalid list response")
    }
  Json::object({ "status": "ready", "tools": tools.to_json() }).stringify()
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
  let result = @protocol.decode_mcp_result(response, expected_id=request_id) catch {
    _ => return wasm_error("mcp_protocol_error", "invalid call response")
  }
  Json::object({ "status": "ready", "result": result }).stringify()
}
