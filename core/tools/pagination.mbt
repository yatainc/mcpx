///|
priv struct ToolPagination {
  max_pages : Int32
  max_tools : Int32
  seen_cursors : @hashset.HashSet[String]
  mut pages : Int32
  mut tool_count : Int32
  mut next_cursor : String?
}

///|
fn tool_pagination(max_pages~ : Int32, max_tools~ : Int32) -> ToolPagination {
  {
    max_pages,
    max_tools,
    seen_cursors: HashSet([]),
    pages: 0,
    tool_count: 0,
    next_cursor: None,
  }
}

///|
fn ToolPagination::begin_page(
  self : ToolPagination,
) -> String? raise @protocol.McpProtocolError {
  if self.pages >= self.max_pages {
    raise InvalidResponse("tools/list exceeds maximum page count")
  }
  self.pages += 1
  self.next_cursor
}

///|
fn ToolPagination::accept_page(
  self : ToolPagination,
  page : McpToolListPage,
) -> Bool raise @protocol.McpProtocolError {
  if self.tool_count + page.tools.length() > self.max_tools {
    raise InvalidResponse("tools/list exceeds maximum tool count")
  }
  match page.next_cursor {
    Some(cursor) if !self.seen_cursors.add_and_check(cursor) =>
      raise InvalidResponse("tools/list pagination cursor repeated")
    _ => ()
  }
  self.tool_count += page.tools.length()
  self.next_cursor = page.next_cursor
  page.next_cursor is Some(_)
}
