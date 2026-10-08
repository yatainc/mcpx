///|
pub async fn http_mcp_call_tool(
  url~ : String,
  headers~ : Map[String, String],
  tool_name~ : String,
  arguments~ : Json,
  mode? : @config.McpConnectionMode = Auto,
) -> Json raise @core_http.McpHttpClientError {
  let tool_definition = default_tool_catalog_cache.find_tool(
    url, headers, mode, tool_name,
  )
  @core_http.call_tool(
    native_fetch,
    @core_http.http_endpoint(url~, headers~, mode~),
    tool_name~,
    arguments~,
    tool_definition~,
    on_catalog_refresh=result => {
      default_tool_catalog_cache.put(url, headers, mode, result)
    },
  )
}

///|
pub async fn http_mcp_list_tools(
  url~ : String,
  headers~ : Map[String, String],
  mode? : @config.McpConnectionMode = Auto,
) -> Array[@tools.McpToolInfo] raise @core_http.McpHttpClientError {
  match default_tool_catalog_cache.get(url, headers, mode) {
    Some(value) => return value
    None => ()
  }
  let result = @core_http.list_tools_with_cache_hint(
    native_fetch,
    @core_http.http_endpoint(url~, headers~, mode~),
  )
  default_tool_catalog_cache.put(url, headers, mode, result)
  result.tools.copy()
}
