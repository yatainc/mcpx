///|
pub struct McpToolListResult {
  tools : Array[McpToolInfo]
  ttl_ms : Int
  cache_scope : @protocol.McpCacheScope
} derive(Debug)

///|
pub fn mcp_tool_list_result(
  tools~ : Array[McpToolInfo],
  ttl_ms? : Int = 0,
  cache_scope? : @protocol.McpCacheScope = Private,
) -> McpToolListResult {
  { tools, ttl_ms, cache_scope }
}

///|
priv struct ValidatedTool {
  info : McpToolInfo
  bindings : Array[HeaderBinding]
}

///|
priv struct ToolCatalog {
  result : McpToolListResult
  validated_tools : Array[ValidatedTool]
}

///|
fn validate_tool(
  tool : McpToolInfo,
) -> ValidatedTool raise @protocol.McpProtocolError {
  { info: tool, bindings: header_bindings(tool.input_schema) }
}

///|
// HTTP catalogs omit definitions with unusable parameter-header annotations.
pub async fn list_catalog(
  fetch_page : async (String?) -> Json,
  max_pages? : Int = MCP_TOOL_LIST_MAX_PAGES,
  max_tools? : Int = MCP_TOOL_LIST_MAX_TOOLS,
) -> McpToolListResult {
  fetch_catalog(fetch_page, max_pages~, max_tools~).result
}

///|
async fn fetch_catalog(
  fetch_page : async (String?) -> Json,
  max_pages? : Int = MCP_TOOL_LIST_MAX_PAGES,
  max_tools? : Int = MCP_TOOL_LIST_MAX_TOOLS,
) -> ToolCatalog {
  let pagination = tool_pagination(max_pages~, max_tools~)
  let validated_tools : Array[ValidatedTool] = []
  let mut ttl_ms : Int? = None
  let mut cache_scope : @protocol.McpCacheScope? = None
  for ;; {
    let cursor = pagination.begin_page()
    let page = decode_list_result(fetch_page(cursor), modern=true)
    match cache_scope {
      None => cache_scope = Some(page.cache_scope)
      Some(value) if value != page.cache_scope =>
        raise @protocol.InvalidResponse(
          "tools/list pagination cacheScope changed",
        )
      Some(_) => ()
    }
    let has_next = pagination.accept_page(page)
    for tool in page.tools {
      let validated = validate_tool(tool) catch {
        InvalidResponse(_) => continue
        error => raise error
      }
      validated_tools.push(validated)
    }
    ttl_ms = Some(
      match ttl_ms {
        None => page.ttl_ms
        Some(value) => if value < page.ttl_ms { value } else { page.ttl_ms }
      },
    )
    if !has_next {
      break
    }
  }
  {
    result: mcp_tool_list_result(
      tools=validated_tools.map(tool => tool.info),
      ttl_ms=ttl_ms.unwrap_or(0),
      cache_scope=cache_scope.unwrap_or(Private),
    ),
    validated_tools,
  }
}

///|
fn ToolCatalog::find_tool(self : ToolCatalog, name : String) -> ValidatedTool? {
  self.validated_tools
  .search_by(tool => tool.info.name == name)
  .map(index => self.validated_tools[index])
}
