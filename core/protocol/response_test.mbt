///|
test "mcp response: decodes typed modern protocol errors" {
  try
    @protocol.decode_mcp_result(
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
  catch {
    UnsupportedProtocolVersion(requested, supported) => {
      @debug.debug_inspect(requested, content="Some(\"2026-07-28\")")
      @debug.debug_inspect(supported, content="[\"2025-11-25\"]")
    }
    _ => fail("expected unsupported protocol")
  } noraise {
    _ => fail("expected error")
  }
  try
    @protocol.decode_mcp_result(
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
test "mcp response: decodes initialize result and capabilities" {
  let info = @protocol.decode_mcp_initialize_result(
    @protocol.decode_mcp_result(
      {
        "jsonrpc": "2.0",
        "id": 1,
        "result": {
          "protocolVersion": "2025-03-26",
          "capabilities": { "tools": {} },
          "serverInfo": { "name": "srv", "version": "1" },
        },
      },
      expected_id=1,
    ),
  )
  inspect(info.protocol_version, content="2025-03-26")
  @debug.debug_inspect(info.server_name, content="Some(\"srv\")")
  @debug.debug_inspect(info.server_version, content="Some(\"1\")")
  json_inspect(info.capabilities, content={ "tools": {} })
}

///|
test "mcp response: validates complete result type" {
  let complete : Json = { "resultType": "complete", "value": 42 }
  @protocol.require_complete_result(complete)
  @protocol.require_complete_result({ "value": 42 }, required=false)
  for result_type in ["input_required", "extension/unknown"] {
    try
      @protocol.require_complete_result(
        { "resultType": result_type.to_json() },
        required=false,
      )
    catch {
      InvalidResponse(_) => ()
      _ => fail("expected invalid result type")
    } noraise {
      _ => fail("expected error")
    }
  }
  for
    result in [
      Json::empty_object(),
      Json::null(),
      Json::object({ "resultType": 42 }),
    ] {
    try @protocol.require_complete_result(result) catch {
      InvalidResponse(_) => ()
      _ => fail("expected missing result type")
    } noraise {
      _ => fail("expected error")
    }
  }
}

///|
test "mcp response: validates JSON-RPC 2.0 envelope" {
  let invalid : Array[Json] = [
    { "jsonrpc": "1.0", "id": 1, "result": {} },
    { "id": 1, "result": {} },
    {
      "jsonrpc": "2.0",
      "id": 1,
      "result": {},
      "error": { "code": -32601, "message": "ambiguous" },
    },
  ]
  for response in invalid {
    try @protocol.decode_mcp_result(response, expected_id=1) catch {
      InvalidResponse(_) => ()
      _ => fail("expected invalid response")
    } noraise {
      _ => fail("expected error")
    }
  }
}

///|
test "mcp response: rejects integers outside the supported range" {
  let invalid : Array[Json] = [
    { "jsonrpc": "2.0", "id": 2147483648, "result": {} },
    {
      "jsonrpc": "2.0",
      "id": 1,
      "error": { "code": 2147483648, "message": "bad" },
    },
  ]
  for response in invalid {
    try @protocol.decode_mcp_result(response, expected_id=1) catch {
      InvalidResponse(_) => ()
      _ => fail("expected invalid integer")
    } noraise {
      _ => fail("expected error")
    }
  }
}

///|
test "mcp response: rejects malformed JSON-RPC errors" {
  let errors : Array[Json] = [
    { "code": 4.2, "message": "bad" },
    { "code": "-32601", "message": "bad" },
    { "code": -32601 },
    [],
  ]
  for error in errors {
    try
      @protocol.decode_mcp_result(
        { "jsonrpc": "2.0", "id": 1, "error": error },
        expected_id=1,
      )
    catch {
      InvalidResponse(_) => ()
      _ => fail("expected invalid response")
    } noraise {
      _ => fail("expected error")
    }
  }
}

///|
test "mcp client response: rejects id mismatch and surfaces json-rpc errors" {
  try
    @protocol.decode_mcp_result(
      { "jsonrpc": "2.0", "id": 9, "result": {} },
      expected_id=1,
    )
  catch {
    InvalidResponse(message) =>
      inspect(message, content="unexpected response id")
    _ => fail("expected id mismatch")
  } noraise {
    _ => fail("expected error")
  }
  try
    @protocol.decode_mcp_result(
      {
        "jsonrpc": "2.0",
        "id": 1,
        "error": { "code": -32601, "message": "method not found" },
      },
      expected_id=1,
    )
  catch {
    RemoteError(code, message) => {
      inspect(code, content="-32601")
      inspect(message, content="method not found")
    }
    _ => fail("expected remote error")
  } noraise {
    _ => fail("expected error")
  }
}
