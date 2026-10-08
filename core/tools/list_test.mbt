///|
test "mcp response: preserves arbitrary input and output schemas" {
  let tools = decode_list_result({
      "tools": [
        {
          "name": "schema-tool",
          "inputSchema": {
            "type": "object",
            "oneOf": [{ "required": ["id"] }, { "required": ["name"] }],
          },
          "outputSchema": { "type": "array", "items": { "type": "string" } },
        },
      ],
    }).tools
  inspect(
    tools[0].input_schema.stringify().contains("\"oneOf\""),
    content="true",
  )
  json_inspect(tools[0].output_schema.unwrap(), content={
    "type": "array",
    "items": { "type": "string" },
  })
}

///|
test "mcp response: decodes complete modern tool list page" {
  let page = decode_list_result(
    {
      "resultType": "complete",
      "tools": [{ "name": "search", "inputSchema": {} }],
      "nextCursor": "page-2",
      "ttlMs": 60000,
      "cacheScope": "public",
    },
    modern=true,
  )
  inspect(page.tools[0].name, content="search")
  @debug.debug_inspect(page.next_cursor, content="Some(\"page-2\")")
  inspect(page.ttl_ms, content="60000")
  inspect(page.cache_scope == Public, content="true")
}

///|
test "mcp response: defaults legacy tool list page metadata" {
  let page = decode_list_result({ "tools": [] })
  inspect(page.tools.length(), content="0")
  inspect(page.ttl_ms, content="0")
  inspect(page.cache_scope == Private, content="true")
}

///|
test "mcp response: rejects invalid modern tool list result types" {
  for
    result in [
      Json::object({ "resultType": "input_required", "tools": [] }),
      Json::object({ "resultType": "extension/unknown", "tools": [] }),
      Json::object({ "tools": [] }),
    ] {
    try decode_list_result(result, modern=true) catch {
      InvalidResponse(_) => ()
      _ => fail("expected invalid result type")
    } noraise {
      _ => fail("expected error")
    }
  }
}

///|
test "mcp response: validates tool schema fields" {
  let invalid_tools : Array[Json] = [
    { "name": "missing" },
    { "name": "input", "inputSchema": [] },
    { "name": "output", "inputSchema": {}, "outputSchema": "bad" },
    { "name": "description", "description": 42, "inputSchema": {} },
  ]
  for tool in invalid_tools {
    try decode_list_result({ "tools": [tool] }) catch {
      InvalidResponse(_) => ()
      _ => fail("expected invalid tool")
    } noraise {
      _ => fail("expected error")
    }
  }
}

///|
test "mcp response: ignores out-of-range cache TTL hints" {
  for ttl in [2147483648.0, -1.0, 1.5] {
    let page = decode_list_result(
      {
        "resultType": "complete",
        "tools": [],
        "ttlMs": ttl.to_json(),
        "cacheScope": "public",
      },
      modern=true,
    )
    inspect(page.ttl_ms, content="0")
  }
}

///|
test "tools: JSON roundtrip preserves schemas and omits absent fields" {
  let tool = mcp_tool_info(
    name="search",
    description=Some("Search things"),
    input_schema={ "type": "object" },
    output_schema=Some({ "type": "array" }),
  )
  json_inspect(tool.to_json(), content={
    "name": "search",
    "description": "Search things",
    "inputSchema": { "type": "object" },
    "outputSchema": { "type": "array" },
  })
  let absent = mcp_tool_info(name="plain", input_schema={})
  json_inspect(absent.to_json(), content={ "name": "plain", "inputSchema": {} })
  let decoded = decode_list_result({
      "tools": [tool.to_json(), absent.to_json()],
    }).tools
  json_inspect(decoded.to_json(), content=[tool.to_json(), absent.to_json()])
}
