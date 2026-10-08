///|
async test "core http: discovery protocol errors are normalized at the public boundary" {
  for status in [200, 400, 404, 405] {
    for code in [-32020, -32021, -32022] {
      let methods = []
      try
        @http.list_tools(
          request => {
            methods.push(rpc_method(request.body))
            @http.http_response(
              status_code=status,
              content_type=Some("application/json"),
              body=Json::object({
                "jsonrpc": "2.0",
                "id": 1,
                "error": {
                  "code": code.to_json(),
                  "message": "discovery failure",
                },
              }).stringify(),
            )
          },
          @http.http_endpoint(url="https://mcp.example/discovery-error"),
        )
      catch {
        HeaderMismatch(message) => {
          inspect(code, content="-32020")
          inspect(message, content="discovery failure")
        }
        MissingRequiredClientCapability(message) => {
          inspect(code, content="-32021")
          inspect(message, content="discovery failure")
        }
        UnsupportedProtocolVersion(supported) => {
          inspect(code, content="-32022")
          inspect(supported.is_empty(), content="true")
        }
        _ => fail("unexpected discovery error")
      } noraise {
        _ => fail("expected discovery failure")
      }
      inspect(methods.join(","), content="server/discover")
    }
  }
}
