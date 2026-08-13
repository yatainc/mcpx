///|
pub struct McpToolListLimits {
  max_pages : Int
  max_tools : Int
}

///|
pub fn mcp_tool_list_limits(
  max_pages? : Int = MCP_TOOL_LIST_MAX_PAGES,
  max_tools? : Int = MCP_TOOL_LIST_MAX_TOOLS,
) -> McpToolListLimits {
  { max_pages, max_tools }
}

///|
pub(all) suberror McpToolPaginationError {
  TooManyPages
  TooManyTools
  RepeatedCursor
} derive(Debug, Eq)

///|
pub struct McpToolPagination {
  priv tools : Array[McpToolInfo]
  priv seen_cursors : Map[String, Unit]
  priv mut pages : Int
  priv mut next_cursor : String?
}

///|
pub fn mcp_tool_pagination() -> McpToolPagination {
  { tools: [], seen_cursors: Map([]), pages: 0, next_cursor: None }
}

///|
pub fn McpToolPagination::begin_page(
  self : McpToolPagination,
  limits : McpToolListLimits,
) -> Result[String?, McpToolPaginationError] {
  if self.pages >= limits.max_pages {
    return Err(McpToolPaginationError::TooManyPages)
  }
  self.pages = self.pages + 1
  Ok(self.next_cursor)
}

///|
pub fn McpToolPagination::accept_page(
  self : McpToolPagination,
  page : McpToolListPage,
  limits : McpToolListLimits,
) -> Result[Bool, McpToolPaginationError] {
  if self.tools.length() + page.tools.length() > limits.max_tools {
    return Err(McpToolPaginationError::TooManyTools)
  }
  match page.next_cursor {
    Some(cursor) if self.seen_cursors.contains(cursor) =>
      return Err(McpToolPaginationError::RepeatedCursor)
    _ => ()
  }
  for tool in page.tools {
    self.tools.push(tool)
  }
  match page.next_cursor {
    Some(cursor) => {
      self.seen_cursors[cursor] = ()
      self.next_cursor = Some(cursor)
      Ok(true)
    }
    None => {
      self.next_cursor = None
      Ok(false)
    }
  }
}

///|
pub fn McpToolPagination::tools(self : McpToolPagination) -> Array[McpToolInfo] {
  self.tools.copy()
}

///|
pub fn mcp_tool_list_page(
  tools : Array[McpToolInfo],
  next_cursor? : String? = None,
  ttl_ms? : Int = 0,
  cache_scope? : McpCacheScope = McpCacheScope::Private,
) -> McpToolListPage {
  { tools, next_cursor, ttl_ms, cache_scope }
}
