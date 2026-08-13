///|
test "discovery: builds request and decodes canonical discover result" {
  let context = mcp_request_context(
    protocol=McpProtocolVersion::V2026_07_28,
    client_name="mcpx",
    client_version="0.1.4",
  )
  inspect(
    mcp_discover_request(id=1, context)
    .stringify()
    .contains("\"method\":\"server/discover\""),
    content="true",
  )
  let decoded = decode_mcp_discover_response(
    {
      "jsonrpc": "2.0",
      "id": 1,
      "result": {
        "resultType": "complete",
        "supportedVersions": ["2025-11-25", "2026-07-28"],
        "capabilities": { "tools": Json::empty_object() },
        "instructions": "Use tools",
        "_meta": {
          "io.modelcontextprotocol/serverInfo": {
            "name": "fixture",
            "version": "1",
          },
        },
        "ttlMs": 3600000,
        "cacheScope": "public",
      },
    },
    expected_id=1,
  ).unwrap()
  inspect(decoded.protocol_versions.length(), content="2")
  @debug.debug_inspect(decoded.instructions, content="Some(\"Use tools\")")
  inspect(
    decoded.response_meta.server_info.unwrap().stringify(),
    content="{\"name\":\"fixture\",\"version\":\"1\"}",
  )
  inspect(decoded.result_type, content="complete")
  inspect(decoded.ttl_ms, content="3600000")
  inspect(decoded.cache_scope, content="public")
}

///|
test "discovery: accepts deployed RC serverInfo and cache defaults" {
  let decoded = decode_mcp_discover_response(
    {
      "jsonrpc": "2.0",
      "id": 1,
      "result": {
        "resultType": "complete",
        "supportedVersions": ["2026-07-28"],
        "capabilities": Json::empty_object(),
        "serverInfo": { "name": "mcpjam", "version": "1" },
      },
    },
    expected_id=1,
  ).unwrap()
  inspect(decoded.ttl_ms, content="0")
  inspect(decoded.cache_scope, content="private")
  inspect(
    decoded.response_meta.server_info.unwrap().stringify(),
    content="{\"name\":\"mcpjam\",\"version\":\"1\"}",
  )
}

///|
test "discovery: ignores malformed optional cache hints" {
  let decoded = decode_mcp_discover_response(
    {
      "jsonrpc": "2.0",
      "id": 1,
      "result": {
        "resultType": "complete",
        "supportedVersions": ["2026-07-28"],
        "ttlMs": "later",
        "cacheScope": "organization",
      },
    },
    expected_id=1,
  ).unwrap()
  inspect(decoded.ttl_ms, content="0")
  inspect(decoded.cache_scope, content="private")
}

///|
test "discovery: rejects mismatched id and malformed required fields" {
  inspect(
    decode_mcp_discover_response(
      {
        "jsonrpc": "2.0",
        "id": 2,
        "result": {
          "resultType": "complete",
          "supportedVersions": ["2026-07-28"],
        },
      },
      expected_id=1,
    )
    is Err(_),
    content="true",
  )
  inspect(
    decode_mcp_discover_response(
      {
        "jsonrpc": "2.0",
        "id": 1,
        "result": {
          "resultType": "complete",
          "protocolVersions": ["2026-07-28"],
        },
      },
      expected_id=1,
    )
    is Err(_),
    content="true",
  )
  inspect(
    decode_mcp_discover_response(
      {
        "jsonrpc": "2.0",
        "id": 1,
        "result": { "supportedVersions": ["2026-07-28"] },
      },
      expected_id=1,
    )
    is Err(_),
    content="true",
  )
}
