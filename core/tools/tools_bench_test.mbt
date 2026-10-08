///|
test "bench MCP initialize/list/call request sequence" (it : @bench.T) {
  let arguments : Json = { "q": "moonbit" }
  it.bench(() => {
    let init = @protocol.mcp_initialize_request(
      id=1,
      client_name="mcpx",
      client_version="0.1.4",
    )
    let initialized = @protocol.mcp_initialized_notification()
    let list = @protocol.mcp_request(
      2,
      "tools/list",
      Some(list_params().to_json()),
    )
    let call = @protocol.mcp_request(
      3,
      "tools/call",
      Some(call_params("search", arguments).to_json()),
    )
    it.keep(
      init.stringify().length() +
      initialized.stringify().length() +
      list.stringify().length() +
      call.stringify().length(),
    )
  })
}

///|
test "bench MCP decode representative responses" (it : @bench.T) {
  let init_response : Json = {
    "jsonrpc": "2.0",
    "id": 1,
    "result": {
      "protocolVersion": "2025-03-26",
      "capabilities": {},
      "serverInfo": { "name": "srv", "version": "1.0.0" },
    },
  }
  let list_response : Json = {
    "jsonrpc": "2.0",
    "id": 2,
    "result": {
      "tools": [
        {
          "name": "search",
          "description": "Search things",
          "inputSchema": { "type": "object" },
        },
        { "name": "fetch", "inputSchema": { "type": "object" } },
      ],
    },
  }
  let call_response : Json = {
    "jsonrpc": "2.0",
    "id": 3,
    "result": { "content": [{ "type": "text", "text": "ok" }] },
  }
  it.bench(() => {
    let init = @protocol.decode_mcp_initialize_result(
      @protocol.decode_mcp_result(init_response, expected_id=1),
    ) catch {
      _ => abort("unexpected initialize result")
    }
    let tools = decode_list_result(
      @protocol.decode_mcp_result(list_response, expected_id=2),
    ) catch {
      _ => abort("unexpected tools result")
    }
    let result = @protocol.decode_mcp_result(call_response, expected_id=3) catch {
      _ => abort("unexpected call result")
    }
    it.keep((init, tools, result))
  })
}
