///|
test "bench wasm MCP HTTP call host-action reduce flow" (it : @bench.T) {
  let input =
    #|{"mode":"mcp_http_call","url":"https://mcp.example.test/mcp","toolName":"echo","arguments":{"text":"hi"}}
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
  let accepted =
    #|{"ok":true,"statusCode":202,"body":""}
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
  it.bench(() => {
    let run = mcpx_tool_run(input)
    let init_state = bench_state_json(run)
    let initialized = mcpx_tool_reduce(init_state, init_result)
    let initialized_state = bench_state_json(initialized)
    let call_step = mcpx_tool_reduce(initialized_state, accepted)
    let call_state = bench_state_json(call_step)
    let final_output = mcpx_tool_reduce(call_state, call_result)
    it.keep(final_output.length())
  })
}

///|
test "bench wasm cached credentials reduce" (it : @bench.T) {
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
  let result = Json::object({
    "ok": Json::boolean(true),
    "contents": Json::string(file.to_json().stringify()),
  }).stringify()
  let state =
    #|{"phase":"read_credentials","serverName":"github","credentialsPath":"/home/me/.config/mcpx/credentials.json","cacheKey":"github|abcd","nowSeconds":1000}
  it.bench(() => it.keep(mcpx_tool_reduce(state, result).length()))
}

///|
fn bench_state_json(output : String) -> String {
  let parsed = @json.parse(output) catch { _ => abort("expected JSON output") }
  match parsed {
    Object(obj) => obj["state"].stringify()
    _ => abort("expected object")
  }
}
