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
  let page = decode_mcp_modern_tool_list_page(
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
  ).unwrap()
  inspect(page.tools[0].name, content="search")
  @debug.debug_inspect(page.next_cursor, content="Some(\"page-2\")")
  inspect(page.ttl_ms, content="60000")
  inspect(page.cache_scope == McpCacheScope::Public, content="true")
}

///|
test "mcp response: defaults legacy tool list page metadata" {
  let tools = decode_mcp_tool_list_response(
    { "jsonrpc": "2.0", "id": 2, "result": { "tools": [] } },
    expected_id=2,
  ).unwrap()
  inspect(tools.length(), content="0")
}

///|
test "mcp response: rejects invalid modern tool list result types" {
  for result_type in ["input_required", "extension/unknown"] {
    inspect(
      decode_mcp_modern_tool_list_page(
        Json::object({
          "jsonrpc": Json::string("2.0"),
          "id": Json::number(2.0, repr="2"),
          "result": Json::object({
            "resultType": Json::string(result_type),
            "tools": Json::array([]),
          }),
        }),
        expected_id=2,
      )
      is Err(_),
      content="true",
    )
  }
  inspect(
    decode_mcp_modern_tool_list_page(
      { "jsonrpc": "2.0", "id": 2, "result": { "tools": [] } },
      expected_id=2,
    )
    is Err(_),
    content="true",
  )
}

///|
test "mcp response: validates tool schema fields" {
  let missing_schema =
    #|{"name":"missing"}
  let invalid_input =
    #|{"name":"input","inputSchema":[]}
  let invalid_output =
    #|{"name":"output","inputSchema":{},"outputSchema":"bad"}
  let invalid_description =
    #|{"name":"description","description":42,"inputSchema":{}}
  let invalid_tools = [
    missing_schema, invalid_input, invalid_output, invalid_description,
  ]
  for tool in invalid_tools {
    let response = Json::object({
      "jsonrpc": Json::string("2.0"),
      "id": Json::number(1.0, repr="1"),
      "result": Json::object({ "tools": Json::array([@json.parse(tool)]) }),
    })
    inspect(
      decode_mcp_tool_list_response(response, expected_id=1) is Err(_),
      content="true",
    )
  }
}

///|
test "mcp response: ignores out-of-range cache TTL hints" {
  let page = decode_mcp_modern_tool_list_page(
    {
      "jsonrpc": "2.0",
      "id": 1,
      "result": {
        "resultType": "complete",
        "tools": [],
        "ttlMs": 2147483648,
        "cacheScope": "public",
      },
    },
    expected_id=1,
  ).unwrap()
  inspect(page.ttl_ms, content="0")
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
test "mcp response: validates JSON-RPC 2.0 envelope" {
  let wrong_version =
    #|{"jsonrpc":"1.0","id":1,"result":{}}
  let missing_version =
    #|{"id":1,"result":{}}
  let ambiguous =
    #|{"jsonrpc":"2.0","id":1,"result":{},"error":{"code":-32601,"message":"ambiguous"}}
  let invalid : Array[Json] = [
    @json.parse(wrong_version),
    @json.parse(missing_version),
    @json.parse(ambiguous),
  ]
  for response in invalid {
    let result : Result[Json, McpProtocolError] = try
      decode_mcp_result(response, expected_id=1) |> Ok
    catch {
      error => Err(error)
    }
    inspect(result is Err(_), content="true")
  }
}

///|
test "mcp response: rejects integers outside the supported range" {
  let oversized_id = @json.parse(
    (
      #|{"jsonrpc":"2.0","id":2147483648,"result":{}}
    ),
  )
  let id_result : Result[Json, McpProtocolError] = try
    decode_mcp_result(oversized_id, expected_id=2147483647) |> Ok
  catch {
    error => Err(error)
  }
  inspect(
    id_result is Err(McpProtocolError::InvalidResponse(_)),
    content="true",
  )
  let oversized_code = @json.parse(
    (
      #|{"jsonrpc":"2.0","id":1,"error":{"code":2147483648,"message":"bad"}}
    ),
  )
  let code_result : Result[Json, McpProtocolError] = try
    decode_mcp_result(oversized_code, expected_id=1) |> Ok
  catch {
    error => Err(error)
  }
  inspect(
    code_result is Err(McpProtocolError::InvalidResponse(_)),
    content="true",
  )
}

///|
test "mcp response: rejects malformed JSON-RPC errors" {
  let fractional_code =
    #|{"jsonrpc":"2.0","id":1,"error":{"code":4.2,"message":"bad"}}
  let string_code =
    #|{"jsonrpc":"2.0","id":1,"error":{"code":"-32601","message":"bad"}}
  let missing_message =
    #|{"jsonrpc":"2.0","id":1,"error":{"code":-32601}}
  let non_object_error =
    #|{"jsonrpc":"2.0","id":1,"error":[]}
  let malformed = [
    fractional_code, string_code, missing_message, non_object_error,
  ]
  for text in malformed {
    let response = @json.parse(text)
    let result : Result[Json, McpProtocolError] = try
      decode_mcp_result(response, expected_id=1) |> Ok
    catch {
      error => Err(error)
    }
    match result {
      Err(McpProtocolError::InvalidResponse(_)) => ()
      _ => fail("expected invalid response")
    }
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
