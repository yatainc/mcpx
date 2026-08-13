///|
const MCPX_CLIENT_VERSION : String = "0.1.4"

///|
priv enum Negotiation {
  Modern(@protocol.McpProtocolVersion)
  InitializeEra(@protocol.McpProtocolVersion)
}

///|
priv struct ModernToolCatalog {
  result : McpToolListResult
  next_request_id : Int
}

///|
pub async fn list_tools(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
) -> Array[@protocol.McpToolInfo] raise McpHttpClientError {
  list_tools_with_cache_hint(fetch, endpoint).tools
}

///|
pub async fn list_tools_with_cache_hint(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
) -> McpToolListResult raise McpHttpClientError {
  match negotiate(fetch, endpoint) {
    Modern(version) => list_tools_modern(fetch, endpoint, version)
    InitializeEra(version) =>
      mcp_tool_list_result(tools=list_tools_legacy(fetch, endpoint, version))
  }
}

///|
pub async fn call_tool(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  tool_name~ : String,
  arguments~ : Json,
  tool_definition? : @protocol.McpToolInfo? = None,
  on_catalog_refresh? : (McpToolListResult) -> Unit = _ => (),
) -> Json raise McpHttpClientError {
  match negotiate(fetch, endpoint) {
    Modern(version) => {
      let (tool, first_call_id) = match tool_definition {
        Some(tool) if tool.name == tool_name => (tool, 2)
        Some(_) =>
          raise McpHttpClientError::Protocol(
            "cached tool definition name does not match: " + tool_name,
          )
        None => {
          let catalog = fetch_modern_tool_catalog(fetch, endpoint, version)
          let tool = match
            catalog.result.tools.search_by(tool => tool.name == tool_name) {
            Some(index) => catalog.result.tools[index]
            None =>
              raise McpHttpClientError::Protocol(
                "tool not found in validated tools/list: " + tool_name,
              )
          }
          (tool, catalog.next_request_id)
        }
      }
      let bindings = match inspect_mcp_tool_header_bindings(tool.input_schema) {
        Ok(value) => value
        Err(message) => raise McpHttpClientError::Protocol(message)
      }
      let parameter_headers = match
        build_mcp_tool_parameter_headers(bindings, arguments) {
        Ok(value) => value
        Err(message) => raise McpHttpClientError::Protocol(message)
      }
      call_tool_modern(
        fetch,
        endpoint,
        version,
        request_id=first_call_id,
        parameter_headers~,
        tool_name~,
        arguments~,
      ) catch {
        McpHttpClientError::HeaderMismatch(_) => {
          let refreshed = fetch_modern_tool_catalog(
            fetch,
            endpoint,
            version,
            first_request_id=first_call_id + 1,
          )
          let refreshed_tool = match
            refreshed.result.tools.search_by(tool => tool.name == tool_name) {
            Some(index) => refreshed.result.tools[index]
            None =>
              raise McpHttpClientError::Protocol(
                "tool not found after header schema refresh: " + tool_name,
              )
          }
          let refreshed_bindings = match
            inspect_mcp_tool_header_bindings(refreshed_tool.input_schema) {
            Ok(value) => value
            Err(message) => raise McpHttpClientError::Protocol(message)
          }
          let refreshed_headers = match
            build_mcp_tool_parameter_headers(refreshed_bindings, arguments) {
            Ok(value) => value
            Err(message) => raise McpHttpClientError::Protocol(message)
          }
          let result = call_tool_modern(
            fetch,
            endpoint,
            version,
            request_id=refreshed.next_request_id,
            parameter_headers=refreshed_headers,
            tool_name~,
            arguments~,
          )
          on_catalog_refresh(refreshed.result)
          result
        }
        error => raise error
      }
    }
    InitializeEra(version) =>
      call_tool_legacy(fetch, endpoint, version, tool_name~, arguments~)
  }
}

///|
async fn negotiate(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
) -> Negotiation raise McpHttpClientError {
  // An explicit stateful preference selects the initialize lifecycle directly.
  // Only auto mode may downgrade from discovery to initialize-era MCP.
  if endpoint.mode == @config.McpConnectionMode::Stateful {
    return Negotiation::InitializeEra(@protocol.McpProtocolVersion::V2025_11_25)
  }
  let requested = @protocol.McpProtocolVersion::V2026_07_28
  let response = send_discover(fetch, endpoint, requested)
  if is_clear_legacy_signal(response, expected_id=1) {
    if endpoint.mode == @config.McpConnectionMode::Auto {
      return Negotiation::InitializeEra(
        @protocol.McpProtocolVersion::V2025_11_25,
      )
    }
    raise McpHttpClientError::ModeProtocolIncompatible(
      "stateless", "initialize-era",
    )
  }
  let discover = decode_discover_http_response(response) catch {
    McpHttpClientError::UnsupportedProtocolVersion(supported) => {
      let parsed = supported.map(@protocol.parse_mcp_protocol_version)
      match select_compatible_version(endpoint.mode, parsed) {
        Some(version) if version == requested => {
          let retry = send_discover(fetch, endpoint, version)
          return negotiation_from_discover(
            endpoint.mode,
            decode_discover_http_response(retry),
          )
        }
        Some(version) =>
          return match @protocol.mcp_protocol_family(version) {
            @protocol.McpProtocolFamily::InitializeEra =>
              Negotiation::InitializeEra(version)
            @protocol.McpProtocolFamily::StatelessCore => {
              let retry = send_discover(fetch, endpoint, version)
              negotiation_from_discover(
                endpoint.mode,
                decode_discover_http_response(retry),
              )
            }
            @protocol.McpProtocolFamily::Unsupported =>
              raise McpHttpClientError::UnsupportedProtocolVersion(supported)
          }
        None => raise_incompatible_or_unsupported(endpoint.mode, parsed)
      }
    }
    error => raise error
  }
  negotiation_from_discover(endpoint.mode, discover)
}

///|
fn negotiation_from_discover(
  mode : @config.McpConnectionMode,
  discover : @protocol.McpDiscoverInfo,
) -> Negotiation raise McpHttpClientError {
  let selected = match
    select_compatible_version(mode, discover.protocol_versions) {
    Some(value) => value
    None => raise_incompatible_or_unsupported(mode, discover.protocol_versions)
  }
  match @protocol.mcp_protocol_family(selected) {
    @protocol.McpProtocolFamily::StatelessCore => {
      if mode == @config.McpConnectionMode::Stateful {
        raise McpHttpClientError::ModeProtocolIncompatible(
          "stateful", "2026-07-28",
        )
      }
      Negotiation::Modern(selected)
    }
    @protocol.McpProtocolFamily::InitializeEra =>
      Negotiation::InitializeEra(selected)
    @protocol.McpProtocolFamily::Unsupported =>
      raise McpHttpClientError::UnsupportedProtocolVersion([
        @protocol.mcp_protocol_version_to_string(selected),
      ])
  }
}

///|
fn select_compatible_version(
  mode : @config.McpConnectionMode,
  advertised : Array[@protocol.McpProtocolVersion],
) -> @protocol.McpProtocolVersion? {
  match mode {
    @config.McpConnectionMode::Auto =>
      @protocol.newest_compatible_mcp_protocol_version(
        advertised,
        allow_stateless_core=true,
      )
    @config.McpConnectionMode::Stateful =>
      @protocol.newest_compatible_mcp_protocol_version(
        advertised,
        allow_stateless_core=false,
      )
    @config.McpConnectionMode::Stateless =>
      if advertised.contains(@protocol.McpProtocolVersion::V2026_07_28) {
        Some(@protocol.McpProtocolVersion::V2026_07_28)
      } else {
        None
      }
  }
}

///|
fn[T] raise_incompatible_or_unsupported(
  mode : @config.McpConnectionMode,
  advertised : Array[@protocol.McpProtocolVersion],
) -> T raise McpHttpClientError {
  let has_modern = advertised.any(version => {
    @protocol.mcp_protocol_family(version) ==
    @protocol.McpProtocolFamily::StatelessCore
  })
  let has_initialize = advertised.any(version => {
    @protocol.mcp_protocol_family(version) ==
    @protocol.McpProtocolFamily::InitializeEra
  })
  match mode {
    @config.McpConnectionMode::Stateful if has_modern =>
      raise McpHttpClientError::ModeProtocolIncompatible(
        "stateful", "2026-07-28",
      )
    @config.McpConnectionMode::Stateless if has_initialize =>
      raise McpHttpClientError::ModeProtocolIncompatible(
        "stateless", "initialize-era",
      )
    _ =>
      raise McpHttpClientError::UnsupportedProtocolVersion(
        advertised.map(@protocol.mcp_protocol_version_to_string),
      )
  }
}

///|
async fn send_discover(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  version : @protocol.McpProtocolVersion,
) -> HttpResponse raise McpHttpClientError {
  let context = @protocol.mcp_request_context(
    protocol=version,
    client_name="mcpx",
    client_version=MCPX_CLIENT_VERSION,
  )
  post_json(
    fetch,
    endpoint,
    build_modern_headers(endpoint.headers, version, "server/discover", None),
    @protocol.mcp_discover_request(id=1, context),
  )
}

///|
fn decode_discover_http_response(
  response : HttpResponse,
) -> @protocol.McpDiscoverInfo raise McpHttpClientError {
  let json = response_json(response)
  match @protocol.decode_mcp_discover_response(json, expected_id=1) {
    Ok(value) => value
    Err(error) => raise protocol_error_to_http(error)
  }
}

///|
async fn list_tools_modern(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  version : @protocol.McpProtocolVersion,
) -> McpToolListResult raise McpHttpClientError {
  fetch_modern_tool_catalog(fetch, endpoint, version).result
}

///|
async fn fetch_modern_tool_catalog(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  version : @protocol.McpProtocolVersion,
  first_request_id? : Int = 2,
) -> ModernToolCatalog raise McpHttpClientError {
  let tools = []
  let seen_cursors : Array[String] = []
  let mut cursor : String? = None
  let mut request_id = first_request_id
  let mut ttl_ms = 0
  let mut cache_scope : @protocol.McpCacheScope? = None
  for ;; {
    let request = @protocol.mcp_tools_list_request(
      id=request_id,
      client_name="mcpx",
      client_version=MCPX_CLIENT_VERSION,
      cursor~,
    )
    let response = post_json(
      fetch,
      endpoint,
      build_modern_headers(endpoint.headers, version, "tools/list", None),
      request,
    )
    let page = match
      @protocol.decode_mcp_tool_list_page(
        response_json(response, expected_id=request_id),
        expected_id=request_id,
        require_result_type=true,
      ) {
      Ok(value) => value
      Err(error) => raise protocol_error_to_http(error)
    }
    match cache_scope {
      None => cache_scope = Some(page.cache_scope)
      Some(value) if value != page.cache_scope =>
        raise McpHttpClientError::Protocol(
          "tools/list pagination cacheScope changed",
        )
      Some(_) => ()
    }
    for tool in page.tools {
      match inspect_mcp_tool_header_bindings(tool.input_schema) {
        Ok(_) => tools.push(tool)
        Err(_) => ()
      }
    }
    ttl_ms = if request_id == first_request_id {
      page.ttl_ms
    } else if ttl_ms == 0 || page.ttl_ms == 0 {
      0
    } else if page.ttl_ms < ttl_ms {
      page.ttl_ms
    } else {
      ttl_ms
    }
    match page.next_cursor {
      None => break
      Some(next) => {
        if seen_cursors.contains(next) {
          raise McpHttpClientError::Protocol(
            "tools/list pagination cursor repeated",
          )
        }
        seen_cursors.push(next)
        cursor = Some(next)
        request_id = request_id + 1
      }
    }
  }
  let scope_text = match cache_scope {
    Some(@protocol.McpCacheScope::Public) => "public"
    _ => "private"
  }
  {
    result: mcp_tool_list_result(tools~, ttl_ms~, cache_scope=scope_text),
    next_request_id: request_id + 1,
  }
}

///|
async fn call_tool_modern(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  version : @protocol.McpProtocolVersion,
  request_id~ : Int,
  parameter_headers~ : Map[String, String],
  tool_name~ : String,
  arguments~ : Json,
) -> Json raise McpHttpClientError {
  let request = @protocol.mcp_tool_call_request(
    id=request_id,
    name=tool_name,
    arguments~,
    client_name="mcpx",
    client_version=MCPX_CLIENT_VERSION,
  )
  let headers = build_modern_headers(
    endpoint.headers,
    version,
    "tools/call",
    Some(tool_name),
  )
  remove_headers_with_prefix_case_insensitive(headers, "Mcp-Param-")
  for key, value in parameter_headers {
    remove_header_case_insensitive(headers, key)
    headers[key] = value
  }
  let response = post_json(fetch, endpoint, headers, request)
  let json = response_json(response, expected_id=request_id)
  match
    @protocol.decode_mcp_complete_result(
      json,
      expected_id=request_id,
      require_result_type=true,
    ) {
    Ok(value) => value
    Err(error) => raise protocol_error_to_http(error)
  }
}

///|
async fn list_tools_legacy(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  version : @protocol.McpProtocolVersion,
) -> Array[@protocol.McpToolInfo] raise McpHttpClientError {
  let session_id = Ref(None)
  let client = @protocol.mcp_client(
    client_name="mcpx",
    client_version=MCPX_CLIENT_VERSION,
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
    client_name="mcpx",
    client_version=MCPX_CLIENT_VERSION,
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
async fn post_json(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  headers : Map[String, String],
  message : Json,
) -> HttpResponse raise McpHttpClientError {
  fetch({
    http_method: "POST",
    url: endpoint.url,
    headers,
    body: message.stringify(),
  }) catch {
    error => raise McpHttpClientError::Network(error.to_string())
  }
}

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
fn build_headers_legacy(
  base_headers : Map[String, String],
  session_id : String?,
) -> Map[String, String] {
  let headers = base_headers.copy()
  set_header_case_insensitive(headers, "content-type", "application/json")
  set_header_case_insensitive(
    headers, "accept", "application/json, text/event-stream",
  )
  match session_id {
    Some(value) => set_header_case_insensitive(headers, "Mcp-Session-Id", value)
    None => ()
  }
  headers
}

///|
fn build_modern_headers(
  base_headers : Map[String, String],
  version : @protocol.McpProtocolVersion,
  rpc_method : String,
  rpc_name : String?,
) -> Map[String, String] {
  let headers = build_headers_legacy(base_headers, None)
  for
    key in ["Mcp-Session-Id", "MCP-Protocol-Version", "Mcp-Method", "Mcp-Name"] {
    remove_header_case_insensitive(headers, key)
  }
  remove_headers_with_prefix_case_insensitive(headers, "Mcp-Param-")
  headers["MCP-Protocol-Version"] = @protocol.mcp_protocol_version_to_string(
    version,
  )
  headers["Mcp-Method"] = rpc_method
  match rpc_name {
    Some(value) => headers["Mcp-Name"] = encode_mcp_http_header_value(value)
    None => ()
  }
  headers
}

///|
fn is_clear_legacy_signal(response : HttpResponse, expected_id~ : Int) -> Bool {
  let error_code = if response.body.trim().is_empty() {
    None
  } else {
    let json = @json.parse(response.body) catch {
      _ =>
        return response.status_code == 400 ||
          response.status_code == 404 ||
          response.status_code == 405
    }
    recognized_jsonrpc_error_code(json, expected_id~)
  }
  // A valid modern error body identifies a modern server even when the HTTP
  // status is unexpected. In particular, modern unknown methods use -32601.
  if is_recognized_modern_error_code(error_code) {
    return false
  }
  if response.status_code != 400 &&
    response.status_code != 404 &&
    response.status_code != 405 {
    return false
  }
  true
}

///|
fn is_recognized_modern_error_code(code : Int?) -> Bool {
  match code {
    Some(-32601) | Some(-32020) | Some(-32021) | Some(-32022) => true
    _ => false
  }
}

///|
fn recognized_jsonrpc_error_code(json : Json, expected_id~ : Int) -> Int? {
  match json {
    Object(obj) => {
      guard obj.get("jsonrpc") == Some(Json::string("2.0")) else { return None }
      guard obj.get("id") is Some(Number(value, ..)) &&
        value.trunc() == value &&
        value == expected_id.to_double() else {
        return None
      }
      match obj.get("error") {
        Some(Object(error)) =>
          match (error.get("code"), error.get("message")) {
            (Some(Number(value, ..)), Some(String(_))) if value.trunc() == value =>
              Some(value.to_int())
            _ => None
          }
        _ => None
      }
    }
    _ => None
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
fn set_header_case_insensitive(
  headers : Map[String, String],
  name : String,
  value : String,
) -> Unit {
  remove_header_case_insensitive(headers, name)
  headers[name] = value
}

///|
fn remove_header_case_insensitive(
  headers : Map[String, String],
  target : String,
) -> Unit {
  let removals = []
  for key, _ in headers {
    if key.equal_ignore_ascii_case(target) {
      removals.push(key)
    }
  }
  for key in removals {
    headers.remove(key)
  }
}

///|
fn remove_headers_with_prefix_case_insensitive(
  headers : Map[String, String],
  prefix : String,
) -> Unit {
  let normalized = prefix.to_lower()
  let removals = []
  for key, _ in headers {
    if key.to_lower().has_prefix(normalized) {
      removals.push(key)
    }
  }
  for key in removals {
    headers.remove(key)
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

///|
fn header(headers : Map[String, String], key : String) -> String? {
  for name, value in headers {
    if name.equal_ignore_ascii_case(key) {
      return Some(value)
    }
  }
  None
}
