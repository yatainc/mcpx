///|
test "mcp client: pure initialize list and call sequence" {
  let client = mcp_client(client_name="mcpx", client_version="0.1.3")
  let init = client.initialize_request()
  inspect(
    init.message.stringify(),
    content=(
      #|{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2026-07-28","capabilities":{},"clientInfo":{"name":"mcpx","version":"0.1.3"}}}
    ),
  )
  ignore(
    client.accept_initialize_response(
      init,
      Json::object({
        "jsonrpc": Json::string("2.0"),
        "id": Json::number(1.0, repr="1"),
        "result": Json::object({
          "protocolVersion": Json::string("2025-03-26"),
          "capabilities": Json::empty_object(),
          "serverInfo": Json::object({ "name": Json::string("srv") }),
        }),
      }),
    ) catch {
      _ => abort("unexpected mcp protocol error")
    },
  )
  let initialized = client.initialized_notification()
  @debug.debug_inspect(initialized.id, content="None")
  let list = client.tools_list_request()
  @debug.debug_inspect(list.id, content="Some(2)")
  let call = client.tool_call_request(
    name="search",
    arguments=Json::object({ "q": Json::string("moonbit") }),
  )
  @debug.debug_inspect(call.id, content="Some(3)")
}
