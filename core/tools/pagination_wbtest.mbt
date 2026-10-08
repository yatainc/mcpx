///|
fn page(
  tools : Array[McpToolInfo],
  next_cursor? : String? = None,
) -> McpToolListPage {
  { tools, next_cursor, ttl_ms: 0, cache_scope: Private, }
}

///|
test "tool pagination: counts tools and advances cursors" {
  let pagination = tool_pagination(max_pages=3, max_tools=3)
  @debug.debug_inspect(pagination.begin_page(), content="None")
  inspect(
    pagination.accept_page(
      page(
        [mcp_tool_info(name="first", input_schema={})],
        next_cursor=Some("next"),
      ),
    ),
    content="true",
  )
  @debug.debug_inspect(pagination.begin_page(), content="Some(\"next\")")
  inspect(
    pagination.accept_page(
      page([mcp_tool_info(name="second", input_schema={})]),
    ),
    content="false",
  )
  inspect(pagination.tool_count, content="2")
}

///|
test "tool pagination: rejects repeated cursors before accepting page" {
  let pagination = tool_pagination(max_pages=3, max_tools=3)
  ignore(pagination.begin_page())
  ignore(pagination.accept_page(page([], next_cursor=Some("same"))))
  ignore(pagination.begin_page())
  try
    pagination.accept_page(
      page(
        [mcp_tool_info(name="extra", input_schema={})],
        next_cursor=Some("same"),
      ),
    )
  catch {
    InvalidResponse(message) =>
      inspect(message, content="tools/list pagination cursor repeated")
    _ => fail("expected repeated cursor")
  } noraise {
    _ => fail("expected error")
  }
  inspect(pagination.tool_count, content="0")
}

///|
test "tool pagination: enforces page and tool limits before mutation" {
  let pagination = tool_pagination(max_pages=1, max_tools=1)
  ignore(pagination.begin_page())
  ignore(
    pagination.accept_page(
      page(
        [mcp_tool_info(name="kept", input_schema={})],
        next_cursor=Some("more"),
      ),
    ),
  )
  try pagination.begin_page() catch {
    InvalidResponse(message) =>
      inspect(message, content="tools/list exceeds maximum page count")
    _ => fail("expected page limit")
  } noraise {
    _ => fail("expected error")
  }
  try
    pagination.accept_page(page([mcp_tool_info(name="extra", input_schema={})]))
  catch {
    InvalidResponse(message) =>
      inspect(message, content="tools/list exceeds maximum tool count")
    _ => fail("expected tool limit")
  } noraise {
    _ => fail("expected error")
  }
  inspect(pagination.tool_count, content="1")
}
