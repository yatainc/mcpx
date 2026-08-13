///|
async test "core http: strips user protocol headers from legacy requests" {
  let seen : Array[HttpRequest] = []
  ignore(
    list_tools(
      req => {
        seen.push(req)
        match rpc_method(req.body) {
          "initialize" =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              headers={ "Mcp-Session-Id": "issued" },
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
      http_endpoint(
        url="https://mcp.example/legacy-header-scope",
        headers={
          "mcp-session-id": "attacker",
          "Mcp-Method": "attacker",
          "Mcp-Name": "attacker",
          "Mcp-Param-Admin": "true",
        },
        mode=@config.McpConnectionMode::Stateful,
      ),
    ),
  )
  for key in ["Mcp-Session-Id", "Mcp-Method", "Mcp-Name", "Mcp-Param-Admin"] {
    inspect(header(seen[0].headers, key), content="")
  }
  inspect(header(seen[1].headers, "Mcp-Session-Id"), content="issued")
}

///|
async test "core http: reads response headers case-insensitively" {
  let seen : Array[HttpRequest] = []
  ignore(
    list_tools(
      req => {
        seen.push(req)
        match rpc_method(req.body) {
          "initialize" =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              headers={ "MCP-SESSION-ID": "session" },
              body=(
                #|{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","capabilities":{}}}
              ),
            )
          "notifications/initialized" =>
            http_response(
              status_code=202,
              content_type=Some("application/json"),
              body="",
            )
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
      http_endpoint(
        url="https://mcp.example/case-response",
        mode=@config.McpConnectionMode::Stateful,
      ),
    ),
  )
  inspect(header(seen[1].headers, "Mcp-Session-Id"), content="session")
}

///|
async test "core http: preserves legacy JSON-RPC error classification" {
  try
    list_tools(
      req => {
        match rpc_method(req.body) {
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
                #|{"jsonrpc":"2.0","id":2,"error":{"code":-32099,"message":"legacy failure"}}
              ),
            )
        }
      },
      http_endpoint(
        url="https://mcp.example/legacy-error",
        mode=@config.McpConnectionMode::Stateful,
      ),
    )
  catch {
    McpHttpClientError::RemoteError(code, message) => {
      inspect(code, content="-32099")
      inspect(message, content="legacy failure")
    }
    _ => fail("expected remote error")
  } noraise {
    _ => fail("expected legacy call to fail")
  }
}

///|
async test "core http: explicit stateful initializes without discovery" {
  let seen : Array[HttpRequest] = []
  let tools = list_tools(
    req => {
      seen.push(req)
      match rpc_method(req.body) {
        "initialize" =>
          http_response(
            status_code=200,
            content_type=Some("application/json"),
            headers={ "Mcp-Session-Id": "sid123" },
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
    http_endpoint(
      url="https://mcp.example/mcp",
      mode=@config.McpConnectionMode::Stateful,
    ),
  )
  inspect(tools.length(), content="0")
  inspect(
    seen.map(req => rpc_method(req.body)).join(","),
    content="initialize,notifications/initialized,tools/list",
  )
  inspect(header(seen[1].headers, "Mcp-Session-Id"), content="sid123")
  inspect(header(seen[2].headers, "Mcp-Session-Id"), content="sid123")
}
