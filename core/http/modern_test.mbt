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
            #|{"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","tools":[]}}
          ),
        )
      }
    },
    http_endpoint(url="https://mcp.example/mcp"),
  )
  inspect(result.ttl_ms, content="0")
  inspect(result.cache_scope == Private, content="true")
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
  inspect(result.cache_scope == Public, content="true")
}

///|
async test "core http: excludes only tools with invalid HTTP header annotations" {
  let tools = list_tools(
    req => {
      if rpc_method(req.body) == "server/discover" {
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"]}}
          ),
        )
      } else {
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","tools":[{"name":"valid","inputSchema":{"type":"object","properties":{"region":{"type":"string","x-mcp-header":"Region"}}}},{"name":"invalid","inputSchema":{"type":"object","properties":{"value":{"type":"number","x-mcp-header":"Value"}}}},{"name":"plain","inputSchema":{"type":"object"}}],"ttlMs":0,"cacheScope":"private"}}
          ),
        )
      }
    },
    http_endpoint(url="https://mcp.example/header-tools"),
  )
  inspect(tools.map(tool => tool.name).join(","), content="valid,plain")
}

///|
async test "core http: bounds modern tool pagination" {
  let pages = Ref(0)
  try
    list_tools_with_cache_hint(
      req => {
        if rpc_method(req.body) == "server/discover" {
          return http_response(
            status_code=200,
            content_type=Some("application/json"),
            body=(
              #|{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"]}}
            ),
          )
        }
        pages.val = pages.val + 1
        let id = 1 + pages.val
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          body="{\"jsonrpc\":\"2.0\",\"id\":" +
            id.to_string() +
            ",\"result\":{\"resultType\":\"complete\",\"tools\":[{\"name\":\"tool\",\"inputSchema\":{}}],\"nextCursor\":\"cursor-" +
            id.to_string() +
            "\"}}",
        )
      },
      http_endpoint(url="https://mcp.example/bounded-pages"),
      max_pages=2,
      max_tools=10,
    )
  catch {
    Protocol(message) =>
      inspect(message, content="tools/list exceeds maximum page count")
    _ => fail("expected pagination limit")
  } noraise {
    _ => fail("expected pagination limit")
  }
  inspect(pages.val, content="2")
}

///|
async test "core http: bounds modern tool count" {
  try
    list_tools_with_cache_hint(
      req => {
        if rpc_method(req.body) == "server/discover" {
          http_response(
            status_code=200,
            content_type=Some("application/json"),
            body=(
              #|{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"]}}
            ),
          )
        } else {
          http_response(
            status_code=200,
            content_type=Some("application/json"),
            body=(
              #|{"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","tools":[{"name":"one","inputSchema":{}},{"name":"two","inputSchema":{}}]}}
            ),
          )
        }
      },
      http_endpoint(url="https://mcp.example/bounded-tools"),
      max_pages=2,
      max_tools=1,
    )
  catch {
    Protocol(message) =>
      inspect(message, content="tools/list exceeds maximum tool count")
    _ => fail("expected tool limit")
  } noraise {
    _ => fail("expected tool limit")
  }
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
  inspect(result.cache_scope == Public, content="true")
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
    Protocol(_) => ()
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
    Protocol(_) => ()
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
      } else if rpc_method(req.body) == "tools/list" {
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","tools":[{"name":"search","inputSchema":{}}],"ttlMs":0,"cacheScope":"private"}}
          ),
        )
      } else {
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":3,"result":{"resultType":"complete","content":[{"type":"text","text":"ok"}]}}
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
    content="{\"resultType\":\"complete\",\"content\":[{\"type\":\"text\",\"text\":\"ok\"}]}",
  )
  inspect(header(seen[2].headers, "Mcp-Method"), content="tools/call")
  inspect(header(seen[2].headers, "Mcp-Name"), content="search")
  inspect(seen[2].body.contains("\"q\":\"moonbit\""), content="true")
}

///|
async test "core http: mirrors annotated tool arguments into headers" {
  let seen : Array[HttpRequest] = []
  ignore(
    call_tool(
      req => {
        seen.push(req)
        match rpc_method(req.body) {
          "server/discover" =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"]}}
              ),
            )
          "tools/list" =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","tools":[{"name":"execute_sql","inputSchema":{"type":"object","properties":{"region":{"type":"string","x-mcp-header":"Region"}}}}],"ttlMs":0,"cacheScope":"private"}}
              ),
            )
          _ =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":3,"result":{"resultType":"complete","content":[]}}
              ),
            )
        }
      },
      http_endpoint(url="https://mcp.example/mcp"),
      tool_name="execute_sql",
      arguments={ "region": "日本", "query": "select 1" },
    ),
  )
  inspect(
    seen.map(req => rpc_method(req.body)).join(","),
    content="server/discover,tools/list,tools/call",
  )
  inspect(
    header(seen[2].headers, "Mcp-Param-Region"),
    content="=?base64?5pel5pys?=",
  )
}

///|
async test "core http: refreshes tool headers once after HeaderMismatch" {
  let seen : Array[HttpRequest] = []
  ignore(
    call_tool(
      req => {
        seen.push(req)
        let index = seen.length()
        match index {
          1 =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"]}}
              ),
            )
          2 =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","tools":[{"name":"run","inputSchema":{"type":"object","properties":{"region":{"type":"string","x-mcp-header":"Old"}}}}],"ttlMs":0,"cacheScope":"private"}}
              ),
            )
          3 =>
            http_response(
              status_code=400,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":3,"error":{"code":-32020,"message":"headers changed"}}
              ),
            )
          4 =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":4,"result":{"resultType":"complete","tools":[{"name":"run","inputSchema":{"type":"object","properties":{"region":{"type":"string","x-mcp-header":"New"}}}}],"ttlMs":0,"cacheScope":"private"}}
              ),
            )
          _ =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":5,"result":{"resultType":"complete","content":[]}}
              ),
            )
        }
      },
      http_endpoint(url="https://mcp.example/retry-headers"),
      tool_name="run",
      arguments={ "region": "us-west1" },
    ),
  )
  inspect(
    seen.map(req => rpc_method(req.body)).join(","),
    content="server/discover,tools/list,tools/call,tools/list,tools/call",
  )
  inspect(header(seen[2].headers, "Mcp-Param-Old"), content="us-west1")
  inspect(header(seen[4].headers, "Mcp-Param-New"), content="us-west1")
}

///|
async test "core http: encodes unsafe tool names only in HTTP headers" {
  let seen : Array[HttpRequest] = []
  ignore(
    call_tool(
      req => {
        seen.push(req)
        if rpc_method(req.body) == "server/discover" {
          http_response(
            status_code=200,
            content_type=Some("application/json"),
            body=(
              #|{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"]}}
            ),
          )
        } else if rpc_method(req.body) == "tools/list" {
          http_response(
            status_code=200,
            content_type=Some("application/json"),
            body=(
              #|{"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","tools":[{"name":"検索","inputSchema":{}}],"ttlMs":0,"cacheScope":"private"}}
            ),
          )
        } else {
          http_response(
            status_code=200,
            content_type=Some("application/json"),
            body=(
              #|{"jsonrpc":"2.0","id":3,"result":{"resultType":"complete","content":[]}}
            ),
          )
        }
      },
      http_endpoint(url="https://mcp.example/mcp"),
      tool_name="検索",
      arguments=Json::empty_object(),
    ),
  )
  inspect(header(seen[2].headers, "Mcp-Name"), content="=?base64?5qSc57Si?=")
  inspect(seen[2].body.contains("\"name\":\"検索\""), content="true")
}

///|
async test "core http: generated headers replace user headers case-insensitively" {
  let seen : Array[HttpRequest] = []
  ignore(
    call_tool(
      req => {
        seen.push(req)
        match rpc_method(req.body) {
          "server/discover" =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"]}}
              ),
            )
          "tools/list" =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","tools":[{"name":"run","inputSchema":{"type":"object","properties":{"region":{"type":"string","x-mcp-header":"Region"}}}}],"ttlMs":0,"cacheScope":"private"}}
              ),
            )
          _ =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":3,"result":{"resultType":"complete","content":[]}}
              ),
            )
        }
      },
      http_endpoint(url="https://mcp.example/header-sanitizer", headers={
        "mcp-protocol-version": "attacker",
        "mcp-method": "attacker",
        "mcp-name": "attacker",
        "mcp-param-region": "attacker",
        "mcp-session-id": "legacy-session",
        "Content-Type": "text/plain",
        "ACCEPT": "text/plain",
      }),
      tool_name="run",
      arguments={ "region": "safe" },
    ),
  )
  for
    expected in [
      "content-type", "accept", "mcp-protocol-version", "mcp-method", "mcp-name",
      "mcp-param-region",
    ] {
    let mut count = 0
    for key, _ in seen[2].headers {
      if key.equal_ignore_ascii_case(expected) {
        count = count + 1
      }
    }
    inspect(count, content="1")
  }
  inspect(header(seen[2].headers, "Mcp-Method"), content="tools/call")
  inspect(header(seen[2].headers, "Mcp-Name"), content="run")
  inspect(header(seen[2].headers, "Content-Type"), content="application/json")
  inspect(
    header(seen[2].headers, "Accept"),
    content="application/json, text/event-stream",
  )
  inspect(header(seen[2].headers, "Mcp-Param-Region"), content="safe")
  inspect(header(seen[2].headers, "Mcp-Session-Id"), content="")
}

///|
async test "core http: strips parameter headers from non-call requests" {
  let seen : Array[HttpRequest] = []
  ignore(
    list_tools(
      req => {
        seen.push(req)
        match rpc_method(req.body) {
          "server/discover" =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"]}}
              ),
            )
          _ =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","tools":[]}}
              ),
            )
        }
      },
      http_endpoint(url="https://mcp.example/header-scope", headers={
        "MCP-PARAM-ADMIN": "true",
        "mcp-param-region": "attacker",
      }),
    ),
  )
  for request in seen {
    inspect(header(request.headers, "Mcp-Param-Admin"), content="")
    inspect(header(request.headers, "Mcp-Param-Region"), content="")
  }
}

///|
async test "core http: modern tools list requires resultType" {
  try
    list_tools(
      req => {
        match rpc_method(req.body) {
          "server/discover" =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"]}}
              ),
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
      http_endpoint(url="https://mcp.example/result-type"),
    )
  catch {
    Protocol(_) => ()
    _ => fail("expected protocol error")
  } noraise {
    _ => fail("expected missing resultType to fail")
  }
}

///|
async test "core http: removes unannotated user Mcp-Param headers" {
  let seen : Array[HttpRequest] = []
  ignore(
    call_tool(
      req => {
        seen.push(req)
        match rpc_method(req.body) {
          "server/discover" =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"]}}
              ),
            )
          "tools/list" =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","tools":[{"name":"run","inputSchema":{"type":"object"}}]}}
              ),
            )
          _ =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":3,"result":{"resultType":"complete","content":[]}}
              ),
            )
        }
      },
      http_endpoint(url="https://mcp.example/param", headers={
        "mcp-param-admin": "true",
      }),
      tool_name="run",
      arguments=Json::empty_object(),
    ),
  )
  inspect(header(seen[2].headers, "Mcp-Param-Admin"), content="")
}

///|
async test "core http: modern call requires resultType" {
  try
    call_tool(
      req => {
        match rpc_method(req.body) {
          "server/discover" =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"]}}
              ),
            )
          "tools/list" =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","tools":[{"name":"run","inputSchema":{"type":"object"}}]}}
              ),
            )
          _ =>
            http_response(
              status_code=200,
              content_type=Some("application/json"),
              body=(
                #|{"jsonrpc":"2.0","id":3,"result":{"content":[]}}
              ),
            )
        }
      },
      http_endpoint(url="https://mcp.example/call-result-type"),
      tool_name="run",
      arguments=Json::empty_object(),
    )
  catch {
    Protocol(_) => ()
    _ => fail("expected protocol error")
  } noraise {
    _ => fail("expected missing resultType to fail")
  }
}
