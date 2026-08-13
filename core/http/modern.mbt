///|
priv struct ValidatedHttpTool {
  info : @protocol.McpToolInfo
  header_bindings : Array[McpToolHeaderBinding]
}

///|
priv struct ModernToolCatalog {
  result : McpToolListResult
  validated_tools : Array[ValidatedHttpTool]
  next_request_id : Int
}

///|
fn validate_http_tool(
  tool : @protocol.McpToolInfo,
) -> Result[ValidatedHttpTool, String] {
  match inspect_mcp_tool_header_bindings(tool.input_schema) {
    Ok(header_bindings) => Ok({ info: tool, header_bindings })
    Err(message) => Err(message)
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
  let validated_tools : Array[ValidatedHttpTool] = []
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
    for tool in page.tools {
      match validate_http_tool(tool) {
        Ok(validated) => validated_tools.push(validated)
        Err(_) => ()
      }
    }
    let has_next = match pagination.accept_page(page, limits) {
      Ok(value) => value
      Err(error) => raise pagination_error_to_http(error)
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
      tools=validated_tools.map(tool => tool.info),
      ttl_ms~,
      cache_scope=scope,
    ),
    validated_tools,
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
async fn call_tool_modern_with_catalog(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  version : @protocol.McpProtocolVersion,
  tool_name~ : String,
  arguments~ : Json,
  tool_definition~ : @protocol.McpToolInfo?,
  on_catalog_refresh~ : (McpToolListResult) -> Unit,
) -> Json raise McpHttpClientError {
  let (validated_tool, first_call_id) = match tool_definition {
    Some(tool) if tool.name == tool_name => {
      let validated = match validate_http_tool(tool) {
        Ok(value) => value
        Err(message) => raise McpHttpClientError::Protocol(message)
      }
      (validated, 2)
    }
    Some(_) =>
      raise McpHttpClientError::Protocol(
        "cached tool definition name does not match: " + tool_name,
      )
    None => {
      let catalog = fetch_modern_tool_catalog(fetch, endpoint, version)
      let tool = match
        catalog.validated_tools.search_by(tool => tool.info.name == tool_name) {
        Some(index) => catalog.validated_tools[index]
        None =>
          raise McpHttpClientError::Protocol(
            "tool not found in validated tools/list: " + tool_name,
          )
      }
      (tool, catalog.next_request_id)
    }
  }
  let parameter_headers = match
    build_mcp_tool_parameter_headers(validated_tool.header_bindings, arguments) {
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
        refreshed.validated_tools.search_by(tool => tool.info.name == tool_name) {
        Some(index) => refreshed.validated_tools[index]
        None =>
          raise McpHttpClientError::Protocol(
            "tool not found after header schema refresh: " + tool_name,
          )
      }
      let refreshed_headers = match
        build_mcp_tool_parameter_headers(
          refreshed_tool.header_bindings,
          arguments,
        ) {
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
