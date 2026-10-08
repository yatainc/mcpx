///|
pub async fn list_tools(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
) -> Array[@tools.McpToolInfo] raise McpHttpClientError {
  list_tools_with_cache_hint(fetch, endpoint).tools
}

///|
pub async fn list_tools_with_cache_hint(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  max_pages? : Int = @tools.MCP_TOOL_LIST_MAX_PAGES,
  max_tools? : Int = @tools.MCP_TOOL_LIST_MAX_TOOLS,
) -> @tools.McpToolListResult raise McpHttpClientError {
  with_http_errors(() => {
    match negotiate(fetch, endpoint) {
      Modern(version) => {
        let connection = modern_http(fetch, endpoint, version)
        @tools.list_catalog(
          cursor => {
            connection.request("tools/list", @tools.list_params(cursor~))
          },
          max_pages~,
          max_tools~,
        )
      }
      InitializeEra(version) =>
        @tools.mcp_tool_list_result(
          tools=list_tools_legacy(fetch, endpoint, version),
        )
    }
  })
}

///|
pub async fn call_tool(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  tool_name~ : String,
  arguments~ : Json,
  tool_definition? : @tools.McpToolInfo? = None,
  on_catalog_refresh? : (@tools.McpToolListResult) -> Unit = _ => (),
) -> Json raise McpHttpClientError {
  with_http_errors(() => {
    match negotiate(fetch, endpoint) {
      Modern(version) => {
        let connection = modern_http(fetch, endpoint, version)
        @tools.call(
          cursor => {
            connection.request("tools/list", @tools.list_params(cursor~))
          },
          values => {
            let result = connection.request(
              "tools/call",
              @tools.call_params(tool_name, arguments),
              name=Some(tool_name),
              parameter_values=values,
            )
            @protocol.require_complete_result(result)
            result
          },
          tool_name~,
          arguments~,
          tool_definition~,
          on_catalog_refresh~,
        )
      }
      InitializeEra(version) =>
        call_tool_legacy(fetch, endpoint, version, tool_name~, arguments~)
    }
  })
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
    error => raise Network(error.to_string())
  }
}
