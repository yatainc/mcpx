///|
async test "core http: legacy list and call classify matching RPC errors on success and non-success HTTP" {
  for status_code in [200, 400, 401, 403, 404, 405, 500, 503] {
    let fetch = legacy_operation_error_fetch(
      http_response(
        status_code~,
        body=Json::object({
          "jsonrpc": "2.0",
          "id": 2,
          "error": { "code": -32601, "message": "operation missing" },
        }).stringify(),
      ),
    )
    let endpoint = http_endpoint(url="https://example.test/mcp", mode=Stateful)
    let operations : Array[async () -> Unit] = [
      () => ignore(list_tools(fetch, endpoint)),
      () => ignore(call_tool(fetch, endpoint, tool_name="echo", arguments={})),
    ]
    for operation in operations {
      try operation() catch {
        @http.RemoteError(code, message) => {
          inspect(code, content="-32601")
          inspect(message, content="operation missing")
        }
        _ => fail("unexpected legacy error classification")
      } noraise {
        _ => fail("expected RPC error")
      }
    }
  }
}

///|
async test "core http: legacy operations reject mismatched or invalid error response IDs" {
  let response_ids : Array[Json] = [1, 3, Json::null(), "2", 2.5]
  for status_code in [200, 400, 500] {
    for response_id in response_ids {
      let fetch = legacy_operation_error_fetch(
        http_response(
          status_code~,
          body=Json::object({
            "jsonrpc": "2.0",
            "id": response_id,
            "error": { "code": -32601, "message": "operation missing" },
          }).stringify(),
        ),
      )
      let endpoint = http_endpoint(
        url="https://example.test/mcp",
        mode=Stateful,
      )
      let operations : Array[async () -> Unit] = [
        () => ignore(list_tools(fetch, endpoint)),
        () => ignore(call_tool(fetch, endpoint, tool_name="echo", arguments={})),
      ]
      for operation in operations {
        try operation() catch {
          @http.Protocol(_) => ()
          _ => fail("expected invalid response ID to be a protocol error")
        } noraise {
          _ => fail("expected invalid response ID to fail")
        }
      }
    }
  }
}

///|
async test "core http: legacy initialize errors still require request ID one" {
  for status_code in [200, 400, 500] {
    for response_id in [1, 2] {
      let requests : Array[HttpRequest] = []
      let fetch : async (HttpRequest) -> HttpResponse = request => {
        requests.push(request)
        guard @json.parse(request.body)
          is { "id": Number(1, ..), "method": String("initialize"), .. } else {
          fail("expected initialize request")
        }
        http_response(
          status_code~,
          body=Json::object({
            "jsonrpc": "2.0",
            "id": response_id,
            "error": { "code": -32099, "message": "initialize failed" },
          }).stringify(),
        )
      }
      let endpoint = http_endpoint(
        url="https://example.test/mcp",
        mode=Stateful,
      )
      let operations : Array[async () -> Unit] = [
        () => ignore(list_tools(fetch, endpoint)),
        () => ignore(call_tool(fetch, endpoint, tool_name="echo", arguments={})),
      ]
      for operation in operations {
        requests.clear()
        try operation() catch {
          @http.RemoteError(code, message) if response_id == 1 => {
            inspect(code, content="-32099")
            inspect(message, content="initialize failed")
          }
          @http.Protocol(message) if response_id == 2 =>
            inspect(message, content="unexpected response id")
          _ => fail("unexpected initialize error classification")
        } noraise {
          _ => fail("expected initialize error")
        }
        inspect(requests.length(), content="1")
      }
    }
  }
}

///|
async test "core http: legacy non-RPC failures retain HTTP status classification" {
  for status_code in [400, 401, 403, 404, 405, 500, 503] {
    for
      body in ["not JSON", "{}", "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{}}"] {
      let fetch = legacy_operation_error_fetch(
        http_response(status_code~, body~),
      )
      let endpoint = http_endpoint(
        url="https://example.test/mcp",
        mode=Stateful,
      )
      let operations : Array[async () -> Unit] = [
        () => ignore(list_tools(fetch, endpoint)),
        () => ignore(call_tool(fetch, endpoint, tool_name="echo", arguments={})),
      ]
      for operation in operations {
        try operation() catch {
          @http.HttpStatus(code) => assert_eq(code, status_code)
          _ => fail("expected HTTP status error")
        } noraise {
          _ => fail("expected HTTP status error")
        }
      }
    }
  }
}

///|
fn legacy_operation_error_fetch(
  response : HttpResponse,
) -> async (HttpRequest) -> HttpResponse {
  request => {
    match @json.parse(request.body) {
      { "id": Number(1, ..), "method": String("initialize"), .. } =>
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
      { "id": Number(2, ..), "method": String("tools/list" | "tools/call"), .. } =>
        response
      _ => fail("unexpected legacy request")
    }
  }
}
