///|
pub fn mcpx_tool_schema() -> String {
  let obj = Map([])
  obj["name"] = Json::string("mcpx")
  obj["version"] = json_int(1)
  obj["api"] = Json::array([
    Json::string("mcpx_tool_schema"),
    Json::string("mcpx_tool_run"),
    Json::string("mcpx_tool_reduce"),
  ])
  let concept = Map([])
  concept["stateless"] = Json::boolean(true)
  concept["hostActions"] = Json::boolean(true)
  concept["mcpClient"] = Json::boolean(true)
  obj["concept"] = Json::object(concept)
  let input_schema = Map([])
  input_schema["type"] = Json::string("object")
  input_schema["required"] = Json::array([
    Json::string("serverName"),
    Json::string("credentialsPath"),
    Json::string("cacheKey"),
  ])
  obj["inputSchema"] = Json::object(input_schema)
  Json::object(obj).stringify()
}

///|
pub fn mcpx_tool_run(input_json : String) -> String {
  let parsed = @json.parse(input_json) catch {
    _ => return wasm_error("invalid_json", "input must be JSON")
  }
  let obj = expect_object(parsed) catch {
    _ => return wasm_error("invalid_input", "input must be object")
  }
  match obj.get("mode") {
    Some(String("mcp_http_initialize")) => return run_mcp_http_initialize(obj)
    Some(String("mcp_http_list")) =>
      return run_mcp_http_operation(obj, operation="list")
    Some(String("mcp_http_call")) =>
      return run_mcp_http_operation(obj, operation="call")
    _ => ()
  }
  let server_name = expect_string_field(obj, "serverName") catch {
    _ => return wasm_error("invalid_input", "serverName is required")
  }
  let credentials_path = expect_string_field(obj, "credentialsPath") catch {
    _ => return wasm_error("invalid_input", "credentialsPath is required")
  }
  let cache_key = expect_string_field(obj, "cacheKey") catch {
    _ => return wasm_error("invalid_input", "cacheKey is required")
  }
  needs_host_read_credentials(server_name, credentials_path, cache_key)
}

///|
pub fn mcpx_tool_reduce(
  state_json : String,
  host_result_json : String,
) -> String {
  let state = @json.parse(state_json) catch {
    _ => return wasm_error("invalid_json", "state must be JSON")
  }
  let state_obj = expect_object(state) catch {
    _ => return wasm_error("invalid_state", "state must be object")
  }
  let phase = expect_string_field(state_obj, "phase") catch {
    _ => return wasm_error("invalid_state", "phase is required")
  }
  match phase {
    "read_credentials" => reduce_read_credentials(state_obj, host_result_json)
    "mcp_http_initialize" =>
      reduce_mcp_http_initialize(state_obj, host_result_json)
    "mcp_http_initialized" =>
      reduce_mcp_http_initialized(state_obj, host_result_json)
    "mcp_http_list" => reduce_mcp_http_list(state_obj, host_result_json)
    "mcp_http_call" => reduce_mcp_http_call(state_obj, host_result_json)
    _ => wasm_error("invalid_state", "unsupported phase")
  }
}

///|
fn reduce_read_credentials(
  state_obj : Map[String, Json],
  host_result_json : String,
) -> String {
  let server_name = expect_string_field(state_obj, "serverName") catch {
    _ => return wasm_error("invalid_state", "serverName is required")
  }
  let cache_key = expect_string_field(state_obj, "cacheKey") catch {
    _ => return wasm_error("invalid_state", "cacheKey is required")
  }
  let now_seconds = optional_int_field(state_obj, "nowSeconds", default=0)
  let host_result = @json.parse(host_result_json) catch {
    _ => return wasm_error("invalid_json", "host result must be JSON")
  }
  let host_result_obj = expect_object(host_result) catch {
    _ => return wasm_error("invalid_host_result", "host result must be object")
  }
  let ok = expect_bool_field(host_result_obj, "ok") catch {
    _ => return wasm_error("invalid_host_result", "ok is required")
  }
  guard ok else { return reauth_required(server_name) }
  let contents = expect_string_field(host_result_obj, "contents") catch {
    _ => return wasm_error("invalid_host_result", "contents is required")
  }
  let credentials_json = @json.parse(contents) catch {
    _ =>
      return wasm_error("invalid_credentials", "credentials file must be JSON")
  }
  let credentials = @auth.decode_credentials_file(credentials_json) catch {
    _ => return wasm_error("invalid_credentials", "credentials file is invalid")
  }
  match
    @auth.decide_auth_cache(credentials.entries.get(cache_key), now_seconds~) {
    @auth.CachedAuthDecision::UseBearerHeader(header) => ready(header)
    @auth.CachedAuthDecision::RefreshWithToken(refresh_token) =>
      refresh_required(refresh_token)
    @auth.CachedAuthDecision::ReauthRequired => reauth_required(server_name)
  }
}

///|
fn run_mcp_http_initialize(obj : Map[String, Json]) -> String {
  let url = expect_string_field(obj, "url") catch {
    _ => return wasm_error("invalid_input", "url is required")
  }
  let client = @mcp_client.mcp_client(
    client_name="mcpx",
    client_version="0.1.4",
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
    client_version="0.1.4",
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
        client_version="0.1.4",
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
        client_version="0.1.4",
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

///|
fn needs_host_read_credentials(
  server_name : String,
  credentials_path : String,
  cache_key : String,
) -> String {
  let obj = Map([])
  obj["status"] = Json::string("needs_host")
  obj["state"] = read_credentials_state(
    server_name, credentials_path, cache_key,
  )
  obj["actions"] = Json::array([
    @auth.credentials_lookup_action(credentials_path~).to_json(),
  ])
  Json::object(obj).stringify()
}

///|
fn needs_host(state : Json, actions : Array[@host.HostAction]) -> String {
  let obj = Map([])
  obj["status"] = Json::string("needs_host")
  obj["state"] = state
  obj["actions"] = Json::array(actions.map(action => action.to_json()))
  Json::object(obj).stringify()
}

///|
fn copy_optional_fields(
  source~ : Map[String, Json],
  target~ : Map[String, Json],
  fields~ : Array[String],
) -> Unit {
  for field in fields {
    match source.get(field) {
      Some(value) => target[field] = value
      None => ()
    }
  }
}

///|
fn tool_info_json(tool : @mcp_client.McpToolInfo) -> Json {
  let obj = Map([])
  obj["name"] = Json::string(tool.name)
  match tool.description {
    Some(value) => obj["description"] = Json::string(value)
    None => ()
  }
  obj["inputSchema"] = tool.input_schema
  match tool.output_schema {
    Some(value) => obj["outputSchema"] = value
    None => ()
  }
  Json::object(obj)
}

///|
fn mcp_http_headers() -> Map[String, String] {
  {
    "content-type": "application/json",
    "accept": "application/json, text/event-stream",
  }
}

///|
fn read_credentials_state(
  server_name : String,
  credentials_path : String,
  cache_key : String,
) -> Json {
  let state = Map([])
  state["phase"] = Json::string("read_credentials")
  state["serverName"] = Json::string(server_name)
  state["credentialsPath"] = Json::string(credentials_path)
  state["cacheKey"] = Json::string(cache_key)
  Json::object(state)
}

///|
suberror EmbeddedError {
  ExpectedObject
  ExpectedString(String)
} derive(Debug)

///|
fn expect_object(json : Json) -> Map[String, Json] raise EmbeddedError {
  match json {
    Object(obj) => obj
    _ => raise EmbeddedError::ExpectedObject
  }
}

///|
fn expect_string_field(
  obj : Map[String, Json],
  field : String,
) -> String raise EmbeddedError {
  match obj.get(field) {
    Some(String(value)) => value
    _ => raise EmbeddedError::ExpectedString(field)
  }
}

///|
fn expect_bool_field(
  obj : Map[String, Json],
  field : String,
) -> Bool raise EmbeddedError {
  match obj.get(field) {
    Some(True) => true
    Some(False) => false
    _ => raise EmbeddedError::ExpectedString(field)
  }
}

///|
fn expect_int_field(
  obj : Map[String, Json],
  field : String,
) -> Int raise EmbeddedError {
  match obj.get(field) {
    Some(Number(value, ..)) if value.trunc() == value => value.to_int()
    _ => raise EmbeddedError::ExpectedString(field)
  }
}

///|
fn optional_string_field(obj : Map[String, Json], field : String) -> String? {
  match obj.get(field) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn parse_host_result(
  host_result_json : String,
) -> Map[String, Json] raise EmbeddedError {
  let host_result = @json.parse(host_result_json) catch {
    _ => raise EmbeddedError::ExpectedObject
  }
  expect_object(host_result)
}

///|
fn mcp_host_result_json(host_result_json : String) -> Json raise EmbeddedError {
  let host_result_obj = parse_host_result(host_result_json)
  let ok = expect_bool_field(host_result_obj, "ok")
  if !ok {
    raise EmbeddedError::ExpectedObject
  }
  let status_code = expect_int_field(host_result_obj, "statusCode")
  let content_type = optional_string_field(host_result_obj, "contentType")
  let body = expect_string_field(host_result_obj, "body")
  let payload = match
    @mcp_client.decode_mcp_transport_payload(
      @mcp_client.mcp_transport_response(status_code~, content_type~, body~),
    ) {
    Ok(value) => value
    Err(_) => raise EmbeddedError::ExpectedObject
  }
  @mcp_client.expect_json_payload(payload) catch {
    _ => raise EmbeddedError::ExpectedObject
  }
}

///|
fn optional_int_field(
  obj : Map[String, Json],
  field : String,
  default~ : Int,
) -> Int {
  match obj.get(field) {
    Some(Number(value, ..)) if value.trunc() == value => value.to_int()
    _ => default
  }
}

///|
fn ready(authorization_header : String) -> String {
  let obj = Map([])
  obj["status"] = Json::string("ready")
  let headers = Map([])
  headers["Authorization"] = Json::string(authorization_header)
  obj["headers"] = Json::object(headers)
  Json::object(obj).stringify()
}

///|
fn refresh_required(refresh_token : String) -> String {
  let obj = Map([])
  obj["status"] = Json::string("refresh_required")
  obj["refreshToken"] = Json::string(refresh_token)
  Json::object(obj).stringify()
}

///|
fn reauth_required(server_name : String) -> String {
  let obj = Map([])
  obj["status"] = Json::string("reauth_required")
  obj["command"] = Json::string("mcpx auth " + server_name)
  obj["noBrowser"] = Json::boolean(true)
  Json::object(obj).stringify()
}

///|
fn wasm_error(code : String, message : String) -> String {
  let obj = Map([])
  obj["status"] = Json::string("error")
  obj["code"] = Json::string(code)
  obj["message"] = Json::string(message)
  Json::object(obj).stringify()
}

///|
fn json_int(value : Int) -> Json {
  Json::number(Double::from_int(value), repr=value.to_string())
}
