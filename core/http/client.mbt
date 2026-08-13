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
  max_pages? : Int = @protocol.MCP_TOOL_LIST_MAX_PAGES,
  max_tools? : Int = @protocol.MCP_TOOL_LIST_MAX_TOOLS,
) -> McpToolListResult raise McpHttpClientError {
  match negotiate(fetch, endpoint) {
    Modern(version) =>
      list_tools_modern(fetch, endpoint, version, max_pages~, max_tools~)
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
async fn list_tools_modern(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  version : @protocol.McpProtocolVersion,
  max_pages~ : Int,
  max_tools~ : Int,
) -> McpToolListResult raise McpHttpClientError {
  fetch_modern_tool_catalog(fetch, endpoint, version, max_pages~, max_tools~).result
}

///|
async fn fetch_modern_tool_catalog(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  version : @protocol.McpProtocolVersion,
  first_request_id? : Int = 2,
  max_pages? : Int = @protocol.MCP_TOOL_LIST_MAX_PAGES,
  max_tools? : Int = @protocol.MCP_TOOL_LIST_MAX_TOOLS,
) -> ModernToolCatalog raise McpHttpClientError {
  let pagination = @protocol.mcp_tool_pagination()
  let limits = @protocol.mcp_tool_list_limits(max_pages~, max_tools~)
  let accepted_tools : Array[@protocol.McpToolInfo] = []
  let mut request_id = first_request_id
  let mut ttl_ms = 0
  let mut cache_scope : @protocol.McpCacheScope? = None
  for ;; {
    let cursor = match pagination.begin_page(limits) {
      Ok(value) => value
      Err(error) => raise pagination_error_to_http(error)
    }
    let request = @protocol.mcp_tools_list_request(
      id=request_id,
      client_name=@protocol.MCPX_CLIENT_NAME,
      client_version=@protocol.MCPX_CLIENT_VERSION,
      cursor~,
    )
    let response = post_json(
      fetch,
      endpoint,
      build_modern_headers(endpoint.headers, version, "tools/list", None),
      request,
    )
    let page = match
      @protocol.decode_mcp_modern_tool_list_page(
        response_json(response, expected_id=request_id),
        expected_id=request_id,
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
    let previous_tool_count = pagination.tools().length()
    let has_next = match pagination.accept_page(page, limits) {
      Ok(value) => value
      Err(error) => raise pagination_error_to_http(error)
    }
    let all_tools = pagination.tools()
    for index in previous_tool_count..<all_tools.length() {
      let tool = all_tools[index]
      match inspect_mcp_tool_header_bindings(tool.input_schema) {
        Ok(_) => accepted_tools.push(tool)
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
    if has_next {
      request_id = request_id + 1
    } else {
      break
    }
  }
  let scope = cache_scope.unwrap_or(@protocol.McpCacheScope::Private)
  {
    result: mcp_tool_list_result(
      tools=accepted_tools,
      ttl_ms~,
      cache_scope=scope,
    ),
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
    client_name=@protocol.MCPX_CLIENT_NAME,
    client_version=@protocol.MCPX_CLIENT_VERSION,
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
    @protocol.decode_mcp_modern_complete_result(json, expected_id=request_id) {
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
fn pagination_error_to_http(
  error : @protocol.McpToolPaginationError,
) -> McpHttpClientError {
  match error {
    @protocol.McpToolPaginationError::TooManyPages =>
      McpHttpClientError::Protocol("tools/list exceeds maximum page count")
    @protocol.McpToolPaginationError::TooManyTools =>
      McpHttpClientError::Protocol("tools/list exceeds maximum tool count")
    @protocol.McpToolPaginationError::RepeatedCursor =>
      McpHttpClientError::Protocol("tools/list pagination cursor repeated")
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
