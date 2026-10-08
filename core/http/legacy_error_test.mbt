///|
async test "core http: legacy list and call preserve successful and non-success RPC error classification" {
  for status_code in [200, 400] {
    let fetch : async (HttpRequest) -> HttpResponse = request => {
      match @json.parse(request.body) {
        { "method": String("initialize"), .. } =>
          http_response(
            status_code=200,
            body=Json::object({
              "jsonrpc": "2.0",
              "id": 1,
              "result": { "protocolVersion": "2025-11-25" },
            }).stringify(),
          )
        { "method": String("notifications/initialized"), .. } =>
          http_response(status_code=202, body="")
        _ =>
          http_response(
            status_code~,
            body=Json::object({
              "jsonrpc": "2.0",
              "id": 2,
              "error": { "code": -32601, "message": "operation missing" },
            }).stringify(),
          )
      }
    }
    let endpoint = http_endpoint(url="https://example.test/mcp", mode=Stateful)
    let operations : Array[async () -> Unit] = [
      () => ignore(list_tools(fetch, endpoint)),
      () => ignore(call_tool(fetch, endpoint, tool_name="echo", arguments={})),
    ]
    for operation in operations {
      try operation() catch {
        @http.RemoteError(code, message) if status_code == 200 => {
          inspect(code, content="-32601")
          inspect(message, content="operation missing")
        }
        // Preserve main's existing fixed-ID check on non-success legacy payloads.
        @http.Protocol(message) if status_code == 400 =>
          inspect(message, content="unexpected response id")
        _ => fail("unexpected legacy error classification")
      } noraise {
        _ => fail("expected RPC error")
      }
    }
  }
}
