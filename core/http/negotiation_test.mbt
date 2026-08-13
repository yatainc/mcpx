///|
async test "core http: malformed error body does not prove modern MCP" {
  let seen : Array[String] = []
  ignore(
    list_tools(
      req => {
        let rpc_name = rpc_method(req.body)
        seen.push(rpc_name)
        match rpc_name {
          "server/discover" =>
            http_response(
              status_code=404,
              content_type=Some("application/json"),
              body=(
                #|{"error":{"code":-32601}}
              ),
            )
          "initialize" =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","capabilities":{}}}
              ),
            )
          "notifications/initialized" => http_response(status_code=202, body="")
          _ =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":2,"result":{"tools":[]}}
              ),
            )
        }
      },
      http_endpoint(url="https://mcp.example/malformed-modern-error"),
    ),
  )
  inspect(
    seen.join(","),
    content="server/discover,initialize,notifications/initialized,tools/list",
  )
}

///|
async test "core http: method-not-found identifies a modern server" {
  for status in [200, 400, 404] {
    let seen : Array[String] = []
    try
      list_tools(
        req => {
          seen.push(rpc_method(req.body))
          http_response(
            status_code=status,
            content_type=Some("application/json"),
            body=(
              #|{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"not found"}}
            ),
          )
        },
        http_endpoint(
          url="https://mcp.example/method-not-found-" + status.to_string(),
        ),
      )
    catch {
      RemoteError(code, _) => inspect(code, content="-32601")
      _ => fail("expected modern method-not-found error")
    } noraise {
      _ => fail("expected discovery to fail")
    }
    inspect(seen.join(","), content="server/discover")
  }
}

///|
async test "core http: arbitrary JSON-RPC errors identify a modern server" {
  for status in [400, 404, 405] {
    for code in [-32602, -32603, -32099] {
      let seen : Array[String] = []
      try
        list_tools(
          req => {
            seen.push(rpc_method(req.body))
            http_response(
              status_code=status,
              content_type=Some("application/json"),
              body="{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":" +
                code.to_string() +
                ",\"message\":\"modern error\"}}",
            )
          },
          http_endpoint(
            url="https://mcp.example/arbitrary-error-" +
              status.to_string() +
              "-" +
              code.to_string(),
          ),
        )
      catch {
        RemoteError(actual, _) => inspect(actual, content=code.to_string())
        _ => fail("expected modern JSON-RPC error")
      } noraise {
        _ => fail("expected discovery to fail")
      }
      inspect(seen.join(","), content="server/discover")
    }
  }
}

///|
async test "core http: JSON-RPC results on error statuses do not fall back" {
  for status in [400, 404, 405] {
    let seen : Array[String] = []
    try
      list_tools(
        req => {
          seen.push(rpc_method(req.body))
          http_response(
            status_code=status,
            content_type=Some("application/json"),
            body=(
              #|{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"]}}
            ),
          )
        },
        http_endpoint(
          url="https://mcp.example/result-on-error-" + status.to_string(),
        ),
      )
    catch {
      HttpStatus(actual) => inspect(actual, content=status.to_string())
      _ => fail("expected HTTP status error")
    } noraise {
      _ => fail("expected discovery to fail")
    }
    inspect(seen.join(","), content="server/discover")
  }
}

///|
async test "core http: permitted empty 4xx discovery falls back in auto mode" {
  for status in [400, 404, 405] {
    let seen : Array[String] = []
    ignore(
      list_tools(
        req => {
          let rpc_method_name = rpc_method(req.body)
          seen.push(rpc_method_name)
          match rpc_method_name {
            "server/discover" => http_response(status_code=status, body="")
            "initialize" =>
              http_response(
                status_code=200,
                content_type=Some("application/json"),
                body=(
                  #|{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","capabilities":{}}}
                ),
              )
            "notifications/initialized" =>
              http_response(status_code=202, body="")
            _ =>
              http_response(
                status_code=200,
                content_type=Some("application/json"),
                body=(
                  #|{"jsonrpc":"2.0","id":2,"result":{"tools":[]}}
                ),
              )
          }
        },
        http_endpoint(url="https://mcp.example/empty-4xx-" + status.to_string()),
      ),
    )
    inspect(seen[1], content="initialize")
  }
}

///|
async test "core http: authentication and server errors do not fall back" {
  for status in [401, 403, 408, 429, 500, 503] {
    let seen : Array[String] = []
    try
      list_tools(
        req => {
          seen.push(rpc_method(req.body))
          http_response(status_code=status, body="")
        },
        http_endpoint(
          url="https://mcp.example/no-fallback-" + status.to_string(),
        ),
      )
    catch {
      HttpStatus(actual) => inspect(actual, content=status.to_string())
      _ => fail("expected HTTP status error")
    } noraise {
      _ => fail("expected discovery to fail")
    }
    inspect(seen.join(","), content="server/discover")
  }
}

///|
async test "core http: malformed successful discovery does not fall back" {
  let seen : Array[String] = []
  try
    list_tools(
      req => {
        seen.push(rpc_method(req.body))
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          body="not json",
        )
      },
      http_endpoint(url="https://mcp.example/malformed-discovery"),
    )
  catch {
    Protocol(_) => ()
    _ => fail("expected protocol error")
  } noraise {
    _ => fail("expected discovery to fail")
  }
  inspect(seen.join(","), content="server/discover")
}

///|
async test "core http: explicit stateless preserves modern method-not-found" {
  let methods : Array[String] = []
  try
    list_tools(
      req => {
        methods.push(rpc_method(req.body))
        http_response(
          status_code=404,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"not found"}}
          ),
        )
      },
      http_endpoint(url="https://mcp.example/mcp", mode=Stateless),
    )
  catch {
    RemoteError(code, _) => inspect(code, content="-32601")
    _ => fail("expected modern method-not-found error")
  } noraise {
    _ => fail("expected stateless negotiation to fail")
  }
  inspect(methods.join(","), content="server/discover")
}

///|
async test "core http: modern error must match discovery request id" {
  let seen : Array[String] = []
  ignore(
    list_tools(
      req => {
        let rpc_name = rpc_method(req.body)
        seen.push(rpc_name)
        match rpc_name {
          "server/discover" =>
            http_response(
              status_code=404,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":999,"error":{"code":-32601,"message":"wrong request"}}
              ),
            )
          "initialize" =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","capabilities":{}}}
              ),
            )
          "notifications/initialized" => http_response(status_code=202, body="")
          _ =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":2,"result":{"tools":[]}}
              ),
            )
        }
      },
      http_endpoint(url="https://mcp.example/wrong-id"),
    ),
  )
  inspect(
    seen.join(","),
    content="server/discover,initialize,notifications/initialized,tools/list",
  )
}
