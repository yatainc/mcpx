///|
test "wasm: schema describes stateless host-action API" {
  inspect(
    mcpx_tool_schema(),
    content=(
      #|{"name":"mcpx","version":1,"api":["mcpx_tool_schema","mcpx_tool_run","mcpx_tool_reduce"],"concept":{"stateless":true,"hostActions":true,"mcpClient":true},"inputSchema":{"type":"object","required":["serverName","credentialsPath","cacheKey"]}}
    ),
  )
}

///|
test "wasm: run plans credentials read as host action" {
  let input =
    #|{"serverName":"github","credentialsPath":"/home/me/.config/mcpx/credentials.json","cacheKey":"github|abcd"}
  inspect(
    mcpx_tool_run(input),
    content=(
      #|{"status":"needs_host","state":{"phase":"read_credentials","serverName":"github","credentialsPath":"/home/me/.config/mcpx/credentials.json","cacheKey":"github|abcd"},"actions":[{"kind":"read_text_file","path":"/home/me/.config/mcpx/credentials.json"}]}
    ),
  )
}

///|
test "wasm: reduce valid cached credentials to bearer header" {
  let file = @auth.put_credentials_entry(
    @auth.empty_credentials_file(),
    "github|abcd",
    @auth.credentials_entry(
      server_name="github",
      access_token="access-1",
      refresh_token=Some("refresh-1"),
      expires_at=Some(2000),
      updated_at="2026-05-16T00:00:00.000Z",
    ),
  )
  let result = Map([])
  result["ok"] = Json::boolean(true)
  result["contents"] = Json::string(file.to_json().stringify())
  let state =
    #|{"phase":"read_credentials","serverName":"github","credentialsPath":"/home/me/.config/mcpx/credentials.json","cacheKey":"github|abcd","nowSeconds":1000}
  inspect(
    mcpx_tool_reduce(state, Json::object(result).stringify()),
    content=(
      #|{"status":"ready","headers":{"Authorization":"Bearer access-1"}}
    ),
  )
}

///|
test "wasm: reduce missing credentials to explicit auth command" {
  let state =
    #|{"phase":"read_credentials","serverName":"github","credentialsPath":"/home/me/.config/mcpx/credentials.json","cacheKey":"github|abcd","nowSeconds":1000}
  let host_result =
    #|{"ok":false,"error":"not found"}
  inspect(
    mcpx_tool_reduce(state, host_result),
    content=(
      #|{"status":"reauth_required","command":"mcpx auth github","noBrowser":true}
    ),
  )
}

///|
test "wasm: run can plan MCP initialize over host HTTP using core client" {
  let input =
    #|{"mode":"mcp_http_initialize","url":"http://localhost:3000/mcp"}
  inspect(
    mcpx_tool_run(input),
    content=(
      #|{"status":"needs_host","state":{"phase":"mcp_http_initialize","url":"http://localhost:3000/mcp","requestId":1},"actions":[{"kind":"http_request","method":"POST","url":"http://localhost:3000/mcp","headers":{"content-type":"application/json","accept":"application/json, text/event-stream"},"body":"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2026-07-28\",\"capabilities\":{},\"clientInfo\":{\"name\":\"mcpx\",\"version\":\"0.1.4\"}}}"}]}
    ),
  )
}

///|
test "wasm: reduce MCP initialize response to initialized notification action" {
  let state =
    #|{"phase":"mcp_http_initialize","url":"http://localhost:3000/mcp","requestId":1}
  let body = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0, repr="1"),
    "result": Json::object({
      "protocolVersion": Json::string("2026-07-28"),
      "capabilities": Json::empty_object(),
      "serverInfo": Json::object({ "name": Json::string("srv") }),
    }),
  }).stringify()
  let host_result = Json::object({
    "ok": Json::boolean(true),
    "statusCode": Json::number(200.0, repr="200"),
    "contentType": Json::string("application/json"),
    "body": Json::string(body),
  }).stringify()
  inspect(
    mcpx_tool_reduce(state, host_result),
    content=(
      #|{"status":"needs_host","state":{"phase":"mcp_http_initialized","url":"http://localhost:3000/mcp"},"actions":[{"kind":"http_request","method":"POST","url":"http://localhost:3000/mcp","headers":{"content-type":"application/json","accept":"application/json, text/event-stream"},"body":"{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"}]}
    ),
  )
}

///|
test "wasm: MCP HTTP list flow completes through host actions" {
  let input =
    #|{"mode":"mcp_http_list","url":"http://localhost:3000/mcp"}
  let run = mcpx_tool_run(input)
  let run_obj = @json.parse(run)
  let init_state = match run_obj {
    Object(obj) => obj["state"].stringify()
    _ => abort("expected object")
  }
  let init_body = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0, repr="1"),
    "result": Json::object({
      "protocolVersion": Json::string("2026-07-28"),
      "capabilities": Json::empty_object(),
      "serverInfo": Json::object({ "name": Json::string("srv") }),
    }),
  }).stringify()
  let init_result = Json::object({
    "ok": Json::boolean(true),
    "statusCode": Json::number(200.0, repr="200"),
    "contentType": Json::string("application/json"),
    "body": Json::string(init_body),
  }).stringify()
  let initialized = mcpx_tool_reduce(init_state, init_result)
  let initialized_obj = @json.parse(initialized)
  let initialized_state = match initialized_obj {
    Object(obj) => obj["state"].stringify()
    _ => abort("expected object")
  }
  let accepted =
    #|{"ok":true,"statusCode":202,"body":""}
  let list_step = mcpx_tool_reduce(initialized_state, accepted)
  inspect(
    list_step,
    content=(
      #|{"status":"needs_host","state":{"phase":"mcp_http_list","url":"http://localhost:3000/mcp","requestId":2},"actions":[{"kind":"http_request","method":"POST","url":"http://localhost:3000/mcp","headers":{"content-type":"application/json","accept":"application/json, text/event-stream"},"body":"{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{}}"}]}
    ),
  )
  let list_obj = @json.parse(list_step)
  let list_state = match list_obj {
    Object(obj) => obj["state"].stringify()
    _ => abort("expected object")
  }
  let list_body = Json::object({
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
  }).stringify()
  let list_result = Json::object({
    "ok": Json::boolean(true),
    "statusCode": Json::number(200.0, repr="200"),
    "contentType": Json::string("application/json"),
    "body": Json::string(list_body),
  }).stringify()
  inspect(
    mcpx_tool_reduce(list_state, list_result),
    content=(
      #|{"status":"ready","tools":[{"name":"search","description":"Search things","inputSchema":{"type":"object"}}]}
    ),
  )
}

///|
test "wasm: MCP HTTP call flow completes through host actions" {
  let input =
    #|{"mode":"mcp_http_call","url":"http://localhost:3000/mcp","toolName":"echo","arguments":{"text":"hi"}}
  let run = mcpx_tool_run(input)
  let run_obj = @json.parse(run)
  let init_state = match run_obj {
    Object(obj) => obj["state"].stringify()
    _ => abort("expected object")
  }
  let init_body = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0, repr="1"),
    "result": Json::object({
      "protocolVersion": Json::string("2026-07-28"),
      "capabilities": Json::empty_object(),
      "serverInfo": Json::object({ "name": Json::string("srv") }),
    }),
  }).stringify()
  let init_result = Json::object({
    "ok": Json::boolean(true),
    "statusCode": Json::number(200.0, repr="200"),
    "contentType": Json::string("application/json"),
    "body": Json::string(init_body),
  }).stringify()
  let initialized = mcpx_tool_reduce(init_state, init_result)
  let initialized_obj = @json.parse(initialized)
  let initialized_state = match initialized_obj {
    Object(obj) => obj["state"].stringify()
    _ => abort("expected object")
  }
  let accepted =
    #|{"ok":true,"statusCode":202,"body":""}
  let call_step = mcpx_tool_reduce(initialized_state, accepted)
  inspect(
    call_step,
    content=(
      #|{"status":"needs_host","state":{"phase":"mcp_http_call","url":"http://localhost:3000/mcp","requestId":2},"actions":[{"kind":"http_request","method":"POST","url":"http://localhost:3000/mcp","headers":{"content-type":"application/json","accept":"application/json, text/event-stream"},"body":"{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"echo\",\"arguments\":{\"text\":\"hi\"}}}"}]}
    ),
  )
  let call_obj = @json.parse(call_step)
  let call_state = match call_obj {
    Object(obj) => obj["state"].stringify()
    _ => abort("expected object")
  }
  let call_body = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(2.0, repr="2"),
    "result": Json::object({
      "content": Json::array([
        Json::object({
          "type": Json::string("text"),
          "text": Json::string("hi"),
        }),
      ]),
    }),
  }).stringify()
  let call_result = Json::object({
    "ok": Json::boolean(true),
    "statusCode": Json::number(200.0, repr="200"),
    "contentType": Json::string("application/json"),
    "body": Json::string(call_body),
  }).stringify()
  inspect(
    mcpx_tool_reduce(call_state, call_result),
    content=(
      #|{"status":"ready","result":{"content":[{"type":"text","text":"hi"}]}}
    ),
  )
}
