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
    Modern(version) =>
      call_tool_modern_with_catalog(
        fetch,
        endpoint,
        version,
        tool_name~,
        arguments~,
        tool_definition~,
        on_catalog_refresh~,
      )
    InitializeEra(version) =>
      call_tool_legacy(fetch, endpoint, version, tool_name~, arguments~)
  }
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
