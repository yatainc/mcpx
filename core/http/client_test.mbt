///|
async test "core http: auto discovers then lists over MCP 2026" {
  let seen : Array[HttpRequest] = []
  let tools = list_tools(
    req => {
      seen.push(req)
      if rpc_method(req.body) == "server/discover" {
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"],"capabilities":{},"_meta":{"io.modelcontextprotocol/serverInfo":{"name":"mock","version":"1"}}}}
          ),
        )
      } else {
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"search","inputSchema":{"type":"object"}}]}}
          ),
        )
      }
    },
    http_endpoint(url="https://mcp.example/mcp"),
  )
  inspect(tools[0].name, content="search")
  inspect(
    seen.map(req => rpc_method(req.body)).join(","),
    content="server/discover,tools/list",
  )
  inspect(header(seen[0].headers, "Mcp-Method"), content="server/discover")
  inspect(header(seen[1].headers, "Mcp-Method"), content="tools/list")
  inspect(header(seen[1].headers, "Mcp-Session-Id"), content="")
  inspect(seen[1].body.contains("\"initialize\""), content="false")
}

///|
async test "core http: tool list without cache hints is not cacheable" {
  let result = list_tools_with_cache_hint(
    req => {
      if rpc_method(req.body) == "server/discover" {
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"],"capabilities":{},"ttlMs":60000,"cacheScope":"public"}}
          ),
        )
      } else {
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":2,"result":{"tools":[]}}
          ),
        )
      }
    },
    http_endpoint(url="https://mcp.example/mcp"),
  )
  inspect(result.ttl_ms, content="0")
  inspect(result.cache_scope, content="private")
}

///|
async test "core http: uses tools list cache hints instead of discovery hints" {
  let result = list_tools_with_cache_hint(
    req => {
      if rpc_method(req.body) == "server/discover" {
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"],"capabilities":{},"ttlMs":1,"cacheScope":"private"}}
          ),
        )
      } else {
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","tools":[],"ttlMs":60000,"cacheScope":"public"}}
          ),
        )
      }
    },
    http_endpoint(url="https://mcp.example/tool-cache-hints"),
  )
  inspect(result.ttl_ms, content="60000")
  inspect(result.cache_scope, content="public")
}

///|
async test "core http: combines paginated modern tool lists" {
  let cursors : Array[String] = []
  let result = list_tools_with_cache_hint(
    req => {
      if rpc_method(req.body) == "server/discover" {
        return http_response(
          status_code=200,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"],"capabilities":{},"ttlMs":100,"cacheScope":"private"}}
          ),
        )
      }
      let cursor = rpc_cursor(req.body)
      cursors.push(cursor)
      if cursor.is_empty() {
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","tools":[{"name":"first","inputSchema":{}}],"nextCursor":"page-2","ttlMs":60000,"cacheScope":"public"}}
          ),
        )
      } else {
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":3,"result":{"resultType":"complete","tools":[{"name":"second","inputSchema":{}}],"ttlMs":30000,"cacheScope":"public"}}
          ),
        )
      }
    },
    http_endpoint(url="https://mcp.example/paginated-tools"),
  )
  inspect(result.tools.map(tool => tool.name).join(","), content="first,second")
  inspect(cursors.join(","), content=",page-2")
  inspect(result.ttl_ms, content="30000")
  inspect(result.cache_scope, content="public")
}

///|
async test "core http: rejects inconsistent pagination cache scope" {
  try
    list_tools_with_cache_hint(
      req => {
        if rpc_method(req.body) == "server/discover" {
          http_response(
            status_code=200,
            content_type=Some("application/json"),
            body=(
              #|{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"],"capabilities":{}}}
            ),
          )
        } else if rpc_cursor(req.body).is_empty() {
          http_response(
            status_code=200,
            content_type=Some("application/json"),
            body=(
              #|{"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","tools":[],"nextCursor":"next","ttlMs":60000,"cacheScope":"public"}}
            ),
          )
        } else {
          http_response(
            status_code=200,
            content_type=Some("application/json"),
            body=(
              #|{"jsonrpc":"2.0","id":3,"result":{"resultType":"complete","tools":[],"ttlMs":60000,"cacheScope":"private"}}
            ),
          )
        }
      },
      http_endpoint(url="https://mcp.example/inconsistent-scope"),
    )
  catch {
    McpHttpClientError::Protocol(_) => ()
    _ => fail("expected protocol error")
  } noraise {
    _ => fail("expected pagination to fail")
  }
}

///|
async test "core http: rejects repeated pagination cursor" {
  try
    list_tools_with_cache_hint(
      req => {
        if rpc_method(req.body) == "server/discover" {
          http_response(
            status_code=200,
            content_type=Some("application/json"),
            body=(
              #|{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"],"capabilities":{}}}
            ),
          )
        } else {
          let id = if rpc_cursor(req.body).is_empty() { "2" } else { "3" }
          http_response(
            status_code=200,
            content_type=Some("application/json"),
            body="{\"jsonrpc\":\"2.0\",\"id\":" +
              id +
              ",\"result\":{\"resultType\":\"complete\",\"tools\":[],\"nextCursor\":\"same\",\"ttlMs\":1,\"cacheScope\":\"private\"}}",
          )
        }
      },
      http_endpoint(url="https://mcp.example/cursor-loop"),
    )
  catch {
    McpHttpClientError::Protocol(_) => ()
    _ => fail("expected protocol error")
  } noraise {
    _ => fail("expected pagination to fail")
  }
}

///|
async test "core http: modern call sends method name and preserves arguments" {
  let seen : Array[HttpRequest] = []
  let result = call_tool(
    req => {
      seen.push(req)
      if rpc_method(req.body) == "server/discover" {
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"],"capabilities":{}}}
          ),
        )
      } else {
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"ok"}]}}
          ),
        )
      }
    },
    http_endpoint(url="https://mcp.example/mcp"),
    tool_name="search",
    arguments={ "q": "moonbit" },
  )
  inspect(
    result.stringify(),
    content="{\"content\":[{\"type\":\"text\",\"text\":\"ok\"}]}",
  )
  inspect(header(seen[1].headers, "Mcp-Method"), content="tools/call")
  inspect(header(seen[1].headers, "Mcp-Name"), content="search")
  inspect(seen[1].body.contains("\"q\":\"moonbit\""), content="true")
}

///|
async test "core http: method-not-found discovery falls back and reuses session" {
  let seen : Array[HttpRequest] = []
  let tools = list_tools(
    req => {
      seen.push(req)
      match rpc_method(req.body) {
        "server/discover" =>
          http_response(
            status_code=400,
            content_type=Some("application/json"),
            body=(
              #|{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"not found"}}
            ),
          )
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
              #|{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"search","inputSchema":{}}]}}
            ),
          )
      }
    },
    http_endpoint(url="https://mcp.example/mcp"),
  )
  inspect(tools.length(), content="1")
  inspect(
    seen.map(req => rpc_method(req.body)).join(","),
    content="server/discover,initialize,notifications/initialized,tools/list",
  )
  inspect(header(seen[2].headers, "Mcp-Session-Id"), content="sid123")
  inspect(header(seen[3].headers, "Mcp-Session-Id"), content="sid123")
}

///|
async test "core http: HTTP 200 method-not-found falls back in auto mode" {
  let seen : Array[String] = []
  let tools = list_tools(
    req => {
      let rpc_method_name = rpc_method(req.body)
      seen.push(rpc_method_name)
      match rpc_method_name {
        "server/discover" =>
          http_response(
            status_code=200,
            content_type=Some("application/json"),
            body=(
              #|{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"not found"}}
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
    http_endpoint(url="https://mcp.example/http-200-method-not-found"),
  )
  inspect(tools.length(), content="0")
  inspect(
    seen.join(","),
    content="server/discover,initialize,notifications/initialized,tools/list",
  )
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
      McpHttpClientError::HttpStatus(actual) =>
        inspect(actual, content=status.to_string())
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
    McpHttpClientError::Protocol(_) => ()
    _ => fail("expected protocol error")
  } noraise {
    _ => fail("expected discovery to fail")
  }
  inspect(seen.join(","), content="server/discover")
}

///|
async test "core http: explicit stateless rejects initialize-era fallback" {
  let methods : Array[String] = []
  try
    list_tools(
      req => {
        methods.push(rpc_method(req.body))
        http_response(
          status_code=400,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"not found"}}
          ),
        )
      },
      http_endpoint(
        url="https://mcp.example/mcp",
        mode=@config.McpConnectionMode::Stateless,
      ),
    )
  catch {
    McpHttpClientError::ModeProtocolIncompatible(mode, era) => {
      inspect(mode, content="stateless")
      inspect(era, content="initialize-era")
    }
    _ => fail("expected mode/protocol incompatibility")
  } noraise {
    _ => fail("expected stateless negotiation to fail")
  }
  inspect(methods.join(","), content="server/discover")
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

///|
fn rpc_method(body : String) -> String {
  let parsed = @json.parse(body) catch { _ => return "" }
  match parsed {
    Object(obj) =>
      match obj.get("method") {
        Some(String(value)) => value
        _ => ""
      }
    _ => ""
  }
}

///|
fn rpc_cursor(body : String) -> String {
  let parsed = @json.parse(body) catch { _ => return "" }
  match parsed {
    Object(obj) =>
      match obj.get("params") {
        Some(Object(params)) =>
          match params.get("cursor") {
            Some(String(value)) => value
            _ => ""
          }
        _ => ""
      }
    _ => ""
  }
}

///|
fn header(headers : Map[String, String], key : String) -> String {
  match headers.get(key) {
    Some(value) => value
    None => headers.get(key.to_lower()).unwrap_or("")
  }
}
