///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp http: preserves network errors" {
  try
    http_mcp_list_tools(url="http://127.0.0.1:1/unreachable", headers=Map([]))
  catch {
    error => inspect(mcp_http_is_network_error(error), content="true")
  } noraise {
    _ => fail("expected request failure")
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp http: falls back to initialize then call tool with session" {
  let seen_session = []
  @async.with_task_group(group => {
    let server = @async_http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr.port()
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(allow_failure=true, (request, body, conn) => {
        let text = body.read_all().text()
        let msg = @json.parse(text)
        let rpc_method = match msg {
          Object(obj) =>
            match obj.get("method") {
              Some(String(value)) => value
              _ => ""
            }
          _ => ""
        }
        let id = match msg {
          Object(obj) => obj.get("id").unwrap_or(Json::number(1.0, repr="1"))
          _ => Json::number(1.0, repr="1")
        }
        if rpc_method == "server/discover" {
          conn..send_response(400, "Bad Request").end_response()
        } else if rpc_method == "initialize" {
          let result = Json::object({
            "protocolVersion": Json::string("2025-11-25"),
            "capabilities": Json::empty_object(),
            "serverInfo": Json::object({ "name": Json::string("srv") }),
          })
          conn.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
            "Mcp-Session-Id": "sid123",
          })
          conn
          ..write(
            Json::object({
              "jsonrpc": Json::string("2.0"),
              "id": id,
              "result": result,
            }).stringify(),
          )
          .end_response()
        } else if rpc_method == "notifications/initialized" {
          conn.send_response(202, "Accepted")
          conn.end_response()
        } else if rpc_method == "tools/call" {
          let session = request.headers.get("mcp-session-id").unwrap_or("none")
          if session == "none" {
            conn.send_response(400, "Bad Request", extra_headers={
              "content-type": "application/json",
            })
            conn
            ..write(
              Json::object({
                "jsonrpc": Json::string("2.0"),
                "id": id,
                "error": Json::object({
                  "code": Json::number(-32000.0, repr="-32000"),
                  "message": Json::string(
                    "Bad Request: No valid session ID provided",
                  ),
                }),
              }).stringify(),
            )
            .end_response()
          } else {
            seen_session.push(session)
            conn.send_response(200, "OK", extra_headers={
              "content-type": "application/json",
            })
            conn
            ..write(
              Json::object({
                "jsonrpc": Json::string("2.0"),
                "id": id,
                "result": Json::object({ "ok": Json::boolean(true) }),
              }).stringify(),
            )
            .end_response()
          }
        } else {
          conn.send_response(500, "Unknown")
          conn.end_response()
        }
      })
    })
    let result = http_mcp_call_tool(
      url="http://localhost:\{port}/mcp",
      headers=Map([]),
      tool_name="search",
      arguments=Json::object({ "q": Json::string("moonbit") }),
    )
    inspect(result.stringify(), content="{\"ok\":true}")
  })
  inspect(seen_session.join(","), content="sid123")
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp http: sends MCP 2026 mirrored headers without sessions" {
  let received : Map[String, String] = Map([])
  @async.with_task_group(group => {
    let server = @async_http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr.port()
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(allow_failure=true, (request, body, conn) => {
        let msg = @json.parse(body.read_all().text())
        let rpc_method = match msg {
          Object(obj) =>
            match obj.get("method") {
              Some(String(value)) => value
              _ => ""
            }
          _ => ""
        }
        let id = match msg {
          Object(obj) => obj.get("id").unwrap_or(Json::number(1.0, repr="1"))
          _ => Json::number(1.0, repr="1")
        }
        conn.send_response(200, "OK", extra_headers={
          "content-type": "application/json",
        })
        let result = match rpc_method {
          "server/discover" =>
            Json::object({
              "resultType": Json::string("complete"),
              "supportedVersions": Json::array([Json::string("2026-07-28")]),
            })
          "tools/list" =>
            Json::object({
              "resultType": Json::string("complete"),
              "tools": Json::array([
                Json::object({
                  "name": Json::string("検索"),
                  "inputSchema": @json.parse(
                    (
                      #|{"type":"object","properties":{"region":{"type":"string","x-mcp-header":"Region"}}}
                    ),
                  ),
                }),
              ]),
              "ttlMs": Json::number(0.0, repr="0"),
              "cacheScope": Json::string("private"),
            })
          _ => {
            for key, value in request.headers {
              received[key.to_lower()] = value
            }
            Json::object({
              "resultType": Json::string("complete"),
              "content": Json::array([]),
            })
          }
        }
        conn
        ..write(
          Json::object({
            "jsonrpc": Json::string("2.0"),
            "id": id,
            "result": result,
          }).stringify(),
        )
        .end_response()
      })
    })
    ignore(
      http_mcp_call_tool(
        url="http://localhost:\{port}/mcp",
        headers=Map([]),
        tool_name="検索",
        arguments={ "region": "日本" },
        mode=Stateless,
      ),
    )
  })
  inspect(received["mcp-protocol-version"], content="2026-07-28")
  inspect(received["mcp-method"], content="tools/call")
  inspect(received["mcp-name"], content="=?base64?5qSc57Si?=")
  inspect(received["mcp-param-region"], content="=?base64?5pel5pys?=")
  inspect(received.contains("mcp-session-id"), content="false")
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp http: decodes text event stream JSON-RPC response" {
  @async.with_task_group(group => {
    let server = @async_http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr.port()
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(allow_failure=true, (_request, body, conn) => {
        let msg = @json.parse(body.read_all().text())
        let rpc_method = match msg {
          Object(obj) =>
            match obj.get("method") {
              Some(String(value)) => value
              _ => ""
            }
          _ => ""
        }
        let id = match msg {
          Object(obj) => obj.get("id").unwrap_or(Json::number(1.0, repr="1"))
          _ => Json::number(1.0, repr="1")
        }
        if rpc_method == "server/discover" {
          conn..send_response(400, "Bad Request").end_response()
        } else if rpc_method == "initialize" {
          conn.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
          })
          conn
          ..write(
            Json::object({
              "jsonrpc": Json::string("2.0"),
              "id": id,
              "result": Json::object({
                "protocolVersion": Json::string("2025-03-26"),
                "capabilities": Json::empty_object(),
                "serverInfo": Json::object({ "name": Json::string("srv") }),
              }),
            }).stringify(),
          )
          .end_response()
        } else if rpc_method == "notifications/initialized" {
          conn.send_response(202, "Accepted")
          conn.end_response()
        } else if rpc_method == "tools/call" {
          conn.send_response(200, "OK", extra_headers={
            "content-type": "text/event-stream",
          })
          let payload = Json::object({
            "jsonrpc": Json::string("2.0"),
            "id": id,
            "result": Json::object({ "ok": Json::boolean(true) }),
          }).stringify()
          conn
          ..write("event: message\n")
          ..write("data: " + payload + "\n\n")
          .end_response()
        } else {
          conn.send_response(500, "Unknown")
          conn.end_response()
        }
      })
    })
    let result = http_mcp_call_tool(
      url="http://localhost:\{port}/mcp",
      headers=Map([]),
      tool_name="search",
      arguments=Json::object({ "q": Json::string("moonbit") }),
    )
    inspect(result.stringify(), content="{\"ok\":true}")
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp http: lists tools with stateless request" {
  @async.with_task_group(group => {
    let server = @async_http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr.port()
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(allow_failure=true, (_request, body, conn) => {
        let msg = @json.parse(body.read_all().text())
        let rpc_method = match msg {
          Object(obj) =>
            match obj.get("method") {
              Some(String(value)) => value
              _ => ""
            }
          _ => ""
        }
        let id = match msg {
          Object(obj) => obj.get("id").unwrap_or(Json::number(1.0, repr="1"))
          _ => Json::number(1.0, repr="1")
        }
        if rpc_method == "server/discover" {
          conn..send_response(400, "Bad Request").end_response()
        } else if rpc_method == "initialize" {
          conn.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
            "Mcp-Session-Id": "sid-list",
          })
          conn
          ..write(
            Json::object({
              "jsonrpc": Json::string("2.0"),
              "id": id,
              "result": Json::object({
                "protocolVersion": Json::string("2025-03-26"),
                "capabilities": Json::empty_object(),
                "serverInfo": Json::object({ "name": Json::string("srv") }),
              }),
            }).stringify(),
          )
          .end_response()
        } else if rpc_method == "notifications/initialized" {
          conn.send_response(202, "Accepted")
          conn.end_response()
        } else if rpc_method == "tools/list" {
          conn.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
          })
          conn
          ..write(
            Json::object({
              "jsonrpc": Json::string("2.0"),
              "id": id,
              "result": Json::object({
                "tools": Json::array([
                  Json::object({
                    "name": Json::string("search"),
                    "description": Json::string("Search things"),
                    "inputSchema": Json::object({
                      "type": Json::string("object"),
                    }),
                  }),
                ]),
              }),
            }).stringify(),
          )
          .end_response()
        } else {
          conn.send_response(500, "Unknown")
          conn.end_response()
        }
      })
    })
    let tools = http_mcp_list_tools(
      url="http://localhost:\{port}/mcp",
      headers=Map([]),
    )
    @debug.debug_inspect(
      tools,
      content=(
        #|[
        #|  {
        #|    name: "search",
        #|    description: Some("Search things"),
        #|    input_schema: Object({ "type": String("object") }),
        #|    output_schema: None,
        #|  },
        #|]
      ),
    )
  })
}
