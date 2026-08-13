///|
test "tool pagination: preserves tool order and advances cursors" {
  let pagination = mcp_tool_pagination()
  let limits = mcp_tool_list_limits(max_pages=3, max_tools=3)
  @debug.debug_inspect(pagination.begin_page(limits).unwrap(), content="None")
  inspect(
    pagination
    .accept_page(
      mcp_tool_list_page(
        [mcp_tool_info(name="first", input_schema={})],
        next_cursor=Some("next"),
      ),
      limits,
    )
    .unwrap(),
    content="true",
  )
  @debug.debug_inspect(
    pagination.begin_page(limits).unwrap(),
    content="Some(\"next\")",
  )
  inspect(
    pagination
    .accept_page(
      mcp_tool_list_page([mcp_tool_info(name="second", input_schema={})]),
      limits,
    )
    .unwrap(),
    content="false",
  )
  inspect(
    pagination.tools().map(tool => tool.name).join(","),
    content="first,second",
  )
}

///|
test "tool pagination: tool snapshots cannot mutate accumulator" {
  let pagination = mcp_tool_pagination()
  let limits = mcp_tool_list_limits(max_pages=2, max_tools=2)
  ignore(pagination.begin_page(limits))
  ignore(
    pagination.accept_page(
      mcp_tool_list_page([mcp_tool_info(name="kept", input_schema={})]),
      limits,
    ),
  )
  let snapshot = pagination.tools()
  ignore(snapshot.pop())
  inspect(pagination.tools().map(tool => tool.name).join(","), content="kept")
}

///|
test "tool pagination: rejects repeated cursors" {
  let pagination = mcp_tool_pagination()
  let limits = mcp_tool_list_limits(max_pages=3, max_tools=3)
  ignore(pagination.begin_page(limits).unwrap())
  ignore(
    pagination
    .accept_page(mcp_tool_list_page([], next_cursor=Some("same")), limits)
    .unwrap(),
  )
  ignore(pagination.begin_page(limits).unwrap())
  inspect(
    pagination.accept_page(
      mcp_tool_list_page([], next_cursor=Some("same")),
      limits,
    )
    is Err(RepeatedCursor),
    content="true",
  )
}

///|
test "tool pagination: enforces page and tool limits before mutation" {
  let pagination = mcp_tool_pagination()
  let limits = mcp_tool_list_limits(max_pages=1, max_tools=1)
  ignore(pagination.begin_page(limits).unwrap())
  ignore(
    pagination
    .accept_page(
      mcp_tool_list_page(
        [mcp_tool_info(name="kept", input_schema={})],
        next_cursor=Some("more"),
      ),
      limits,
    )
    .unwrap(),
  )
  inspect(pagination.begin_page(limits) is Err(TooManyPages), content="true")
  inspect(
    pagination.accept_page(
      mcp_tool_list_page([mcp_tool_info(name="extra", input_schema={})]),
      limits,
    )
    is Err(TooManyTools),
    content="true",
  )
  inspect(pagination.tools()[0].name, content="kept")
}
