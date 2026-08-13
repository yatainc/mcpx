///|
test "mcp response: decodes typed modern protocol errors" {
  let unsupported : Result[Json, McpProtocolError] = try
    decode_mcp_result(
      {
        "jsonrpc": "2.0",
        "id": 1,
        "error": {
          "code": -32022,
          "message": "unsupported",
          "data": { "requested": "2026-07-28", "supported": ["2025-11-25"] },
        },
      },
      expected_id=1,
    )
    |> Ok
  catch {
    error => Err(error)
  }
  @debug.debug_inspect(
    unsupported,
    content="Err(UnsupportedProtocolVersion(Some(\"2026-07-28\"), [\"2025-11-25\"]))",
  )
  try
    decode_mcp_result(
      {
        "jsonrpc": "2.0",
        "id": 1,
        "error": { "code": -32020, "message": "bad header" },
      },
      expected_id=1,
    )
  catch {
    HeaderMismatch(message) => inspect(message, content="bad header")
    _ => fail("expected header mismatch")
  } noraise {
    _ => fail("expected error")
  }
}

///|
test "mcp client response: decodes initialize tool list and call result" {
  let init = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0, repr="1"),
    "result": Json::object({
      "protocolVersion": Json::string("2025-03-26"),
      "capabilities": Json::empty_object(),
      "serverInfo": Json::object({ "name": Json::string("srv") }),
    }),
  })
  @debug.debug_inspect(
    decode_mcp_initialize_response(init, expected_id=1),
    content=(
      #|Ok(
      #|  {
      #|    protocol_version: "2025-03-26",
      #|    server_name: Some("srv"),
      #|    server_version: None,
      #|    capabilities: Object({}),
      #|  },
      #|)
    ),
  )
  let list = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(2.0, repr="2"),
    "result": Json::object({
      "tools": Json::array([
        Json::object({
          "name": Json::string("search"),
          "description": Json::string("Search things"),
          "inputSchema": Json::object({ "type": Json::string("object") }),
        }),
      ]),
    }),
  })
  @debug.debug_inspect(
    decode_mcp_tool_list_response(list, expected_id=2),
    content=(
      #|Ok(
      #|  [
      #|    {
      #|      name: "search",
      #|      description: Some("Search things"),
      #|      input_schema: Object({ "type": String("object") }),
      #|      output_schema: None,
      #|    },
      #|  ],
      #|)
    ),
  )
  let call = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(3.0, repr="3"),
    "result": Json::object({ "ok": Json::boolean(true) }),
  })
  inspect(
    (decode_mcp_result(call, expected_id=3) catch { _ => Json::empty_object() }).stringify(),
    content="{\"ok\":true}",
  )
}

///|
test "mcp response: preserves arbitrary input and output schemas" {
  let tools = decode_mcp_tool_list_response(
    {
      "jsonrpc": "2.0",
      "id": 2,
      "result": {
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
      },
    },
    expected_id=2,
  ).unwrap()
  inspect(
    tools[0].input_schema.stringify().contains("\"oneOf\""),
    content="true",
  )
  inspect(
    tools[0].output_schema.unwrap().stringify(),
    content="{\"type\":\"array\",\"items\":{\"type\":\"string\"}}",
  )
}

///|
test "mcp response: decodes complete modern tool list page" {
  let page = decode_mcp_tool_list_page(
    {
      "jsonrpc": "2.0",
      "id": 2,
      "result": {
        "resultType": "complete",
        "tools": [{ "name": "search", "inputSchema": {} }],
        "nextCursor": "page-2",
        "ttlMs": 60000,
        "cacheScope": "public",
      },
    },
    expected_id=2,
    require_result_type=true,
  ).unwrap()
  inspect(page.result_type == McpResultType::Complete, content="true")
  inspect(page.tools[0].name, content="search")
  @debug.debug_inspect(page.next_cursor, content="Some(\"page-2\")")
  inspect(page.ttl_ms, content="60000")
  inspect(page.cache_scope == McpCacheScope::Public, content="true")
}

///|
test "mcp response: defaults legacy tool list page metadata" {
  let page = decode_mcp_tool_list_page(
    { "jsonrpc": "2.0", "id": 2, "result": { "tools": [] } },
    expected_id=2,
    require_result_type=false,
  ).unwrap()
  inspect(page.result_type == McpResultType::Complete, content="true")
  inspect(page.ttl_ms, content="0")
  inspect(page.cache_scope == McpCacheScope::Private, content="true")
}

///|
test "mcp response: rejects invalid modern tool list result types" {
  for result_type in ["input_required", "extension/unknown"] {
    inspect(
      decode_mcp_tool_list_page(
        Json::object({
          "jsonrpc": Json::string("2.0"),
          "id": Json::number(2.0, repr="2"),
          "result": Json::object({
            "resultType": Json::string(result_type),
            "tools": Json::array([]),
          }),
        }),
        expected_id=2,
        require_result_type=true,
      )
      is Err(_),
      content="true",
    )
  }
  inspect(
    decode_mcp_tool_list_page(
      { "jsonrpc": "2.0", "id": 2, "result": { "tools": [] } },
      expected_id=2,
      require_result_type=true,
    )
    is Err(_),
    content="true",
  )
}

///|
test "mcp response: validates complete result type" {
  let complete = decode_mcp_complete_result(
    {
      "jsonrpc": "2.0",
      "id": 3,
      "result": { "resultType": "complete", "value": 42 },
    },
    expected_id=3,
  ).unwrap()
  inspect(
    complete.stringify(),
    content="{\"resultType\":\"complete\",\"value\":42}",
  )
  let legacy = decode_mcp_complete_result(
    { "jsonrpc": "2.0", "id": 3, "result": { "value": 42 } },
    expected_id=3,
  ).unwrap()
  inspect(legacy.stringify(), content="{\"value\":42}")
  for result_type in ["input_required", "extension/unknown"] {
    inspect(
      decode_mcp_complete_result(
        Json::object({
          "jsonrpc": Json::string("2.0"),
          "id": Json::number(3.0, repr="3"),
          "result": Json::object({ "resultType": Json::string(result_type) }),
        }),
        expected_id=3,
      )
      is Err(_),
      content="true",
    )
  }
}

///|
test "mcp client response: rejects id mismatch and surfaces json-rpc errors" {
  let mismatch = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(9.0, repr="9"),
    "result": Json::empty_object(),
  })
  @debug.debug_inspect(
    try decode_mcp_result(mismatch, expected_id=1) |> Ok catch {
      e => Err(e)
    },
    content=(
      #|Err(InvalidResponse("unexpected response id"))
    ),
  )
  let remote_error = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0, repr="1"),
    "error": Json::object({
      "code": Json::number(-32601.0, repr="-32601"),
      "message": Json::string("method not found"),
    }),
  })
  @debug.debug_inspect(
    try decode_mcp_result(remote_error, expected_id=1) |> Ok catch {
      e => Err(e)
    },
    content=(
      #|Err(RemoteError(-32601, "method not found"))
    ),
  )
}
