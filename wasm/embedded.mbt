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
    UseBearerHeader(header) => ready(header)
    RefreshWithToken(refresh_token) => refresh_required(refresh_token)
    ReauthRequired => reauth_required(server_name)
  }
}
