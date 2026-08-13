///|
#cfg(all(target="native", not(platform="windows")))
async test "native http: caches public tool lists across headers" {
  let requests = Ref(0)
  @async.with_task_group(group => {
    let server = @async_http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr.port()
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(allow_failure=true, (request, body, conn) => {
        ignore(request)
        requests.val = requests.val + 1
        let msg = @json.parse(body.read_all().text())
        let rpc_method = rpc_method_from_json(msg)
        let id = rpc_id_from_json(msg)
        conn.send_response(200, "OK", extra_headers={
          "content-type": "application/json",
        })
        if rpc_method == "server/discover" {
          ignore(
            conn.write(
              Json::object({
                "jsonrpc": Json::string("2.0"),
                "id": id,
                "result": Json::object({
                  "resultType": Json::string("complete"),
                  "supportedVersions": Json::array([Json::string("2026-07-28")]),
                  "ttlMs": Json::number(60000.0, repr="60000"),
                  "cacheScope": Json::string("public"),
                }),
              }).stringify(),
            ),
          )
        } else {
          ignore(conn.write(tool_list_response(id, cache_scope="public")))
        }
        conn.end_response()
      })
    })
    let url = "http://localhost:\{port}/public-cache"
    ignore(http_mcp_list_tools(url~, headers={ "Authorization": "Bearer a" }))
    ignore(http_mcp_list_tools(url~, headers={ "Authorization": "Bearer b" }))
    inspect(requests.val, content="2")
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "native http: keeps private tool caches separated by headers" {
  let requests = Ref(0)
  @async.with_task_group(group => {
    let server = @async_http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr.port()
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(allow_failure=true, (_request, body, conn) => {
        requests.val = requests.val + 1
        let msg = @json.parse(body.read_all().text())
        let rpc_method = rpc_method_from_json(msg)
        let id = rpc_id_from_json(msg)
        conn.send_response(200, "OK", extra_headers={
          "content-type": "application/json",
        })
        if rpc_method == "server/discover" {
          ignore(
            conn.write(
              Json::object({
                "jsonrpc": Json::string("2.0"),
                "id": id,
                "result": Json::object({
                  "resultType": Json::string("complete"),
                  "supportedVersions": Json::array([Json::string("2026-07-28")]),
                  "ttlMs": Json::number(60000.0, repr="60000"),
                  "cacheScope": Json::string("private"),
                }),
              }).stringify(),
            ),
          )
        } else {
          ignore(conn.write(tool_list_response(id, cache_scope="private")))
        }
        conn.end_response()
      })
    })
    let url = "http://localhost:\{port}/private-cache"
    ignore(http_mcp_list_tools(url~, headers={ "Authorization": "Bearer a" }))
    ignore(http_mcp_list_tools(url~, headers={ "Authorization": "Bearer a" }))
    ignore(http_mcp_list_tools(url~, headers={ "Authorization": "Bearer b" }))
    inspect(requests.val, content="4")
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "native http: reuses cached tool schema for calls" {
  let methods : Array[String] = []
  @async.with_task_group(group => {
    let server = @async_http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr.port()
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(allow_failure=true, (_request, body, conn) => {
        let msg = @json.parse(body.read_all().text())
        let rpc_method = rpc_method_from_json(msg)
        methods.push(rpc_method)
        let id = rpc_id_from_json(msg)
        conn.send_response(200, "OK", extra_headers={
          "content-type": "application/json",
        })
        let response = if rpc_method == "server/discover" {
          Json::object({
            "jsonrpc": Json::string("2.0"),
            "id": id,
            "result": Json::object({
              "resultType": Json::string("complete"),
              "supportedVersions": Json::array([Json::string("2026-07-28")]),
            }),
          }).stringify()
        } else if rpc_method == "tools/list" {
          tool_list_response(id, cache_scope="private")
        } else {
          Json::object({
            "jsonrpc": Json::string("2.0"),
            "id": id,
            "result": Json::object({
              "resultType": Json::string("complete"),
              "content": Json::array([]),
            }),
          }).stringify()
        }
        ignore(conn.write(response))
        conn.end_response()
      })
    })
    let url = "http://localhost:\{port}/call-cache"
    ignore(http_mcp_list_tools(url~, headers=Map([])))
    ignore(
      http_mcp_call_tool(
        url~,
        headers=Map([]),
        tool_name="search",
        arguments=Json::empty_object(),
      ),
    )
    ignore(
      http_mcp_call_tool(
        url~,
        headers=Map([]),
        tool_name="search",
        arguments=Json::empty_object(),
      ),
    )
  })
  inspect(
    methods.join(","),
    content="server/discover,tools/list,server/discover,tools/call,server/discover,tools/call",
  )
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "native http: caches catalogs discovered by direct calls" {
  let methods : Array[String] = []
  @async.with_task_group(group => {
    let server = @async_http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr.port()
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(allow_failure=true, (_request, body, conn) => {
        let msg = @json.parse(body.read_all().text())
        let rpc_method = rpc_method_from_json(msg)
        methods.push(rpc_method)
        let id = rpc_id_from_json(msg)
        conn.send_response(200, "OK", extra_headers={
          "content-type": "application/json",
        })
        let response = if rpc_method == "server/discover" {
          discover_response(id)
        } else if rpc_method == "tools/list" {
          tool_list_response(id, cache_scope="private")
        } else {
          Json::object({
            "jsonrpc": Json::string("2.0"),
            "id": id,
            "result": Json::object({
              "resultType": Json::string("complete"),
              "content": Json::array([]),
            }),
          }).stringify()
        }
        ignore(conn.write(response))
        conn.end_response()
      })
    })
    let url = "http://localhost:\{port}/direct-call-cache"
    for _ in 0..<2 {
      ignore(
        http_mcp_call_tool(
          url~,
          headers=Map([]),
          tool_name="search",
          arguments=Json::empty_object(),
        ),
      )
    }
  })
  inspect(
    methods.join(","),
    content="server/discover,tools/list,tools/call,server/discover,tools/call",
  )
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "native http: cached tool arrays are isolated from callers" {
  let requests = Ref(0)
  @async.with_task_group(group => {
    let server = @async_http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr.port()
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(allow_failure=true, (_request, body, conn) => {
        requests.val = requests.val + 1
        let msg = @json.parse(body.read_all().text())
        let rpc_name = rpc_method_from_json(msg)
        let id = rpc_id_from_json(msg)
        conn.send_response(200, "OK", extra_headers={
          "content-type": "application/json",
        })
        let response = if rpc_name == "server/discover" {
          discover_response(id)
        } else {
          tool_list_response(id, cache_scope="private")
        }
        ignore(conn.write(response))
        conn.end_response()
      })
    })
    let url = "http://localhost:\{port}/array-isolation"
    let first = http_mcp_list_tools(url~, headers=Map([]))
    match first[0].input_schema {
      Object(schema) => schema["poison"] = Json::boolean(true)
      _ => ()
    }
    ignore(first.pop())
    let second = http_mcp_list_tools(url~, headers=Map([]))
    inspect(second.length(), content="1")
    inspect(second[0].input_schema.stringify(), content="{}")
    inspect(requests.val, content="2")
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "native http: caches refreshed schema after HeaderMismatch" {
  let methods : Array[String] = []
  let list_count = Ref(0)
  @async.with_task_group(group => {
    let server = @async_http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr.port()
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(allow_failure=true, (request, body, conn) => {
        let msg = @json.parse(body.read_all().text())
        let rpc_name = rpc_method_from_json(msg)
        methods.push(rpc_name)
        let id = rpc_id_from_json(msg)
        conn.send_response(200, "OK", extra_headers={
          "content-type": "application/json",
        })
        let response = if rpc_name == "server/discover" {
          discover_response(id)
        } else if rpc_name == "tools/list" {
          list_count.val = list_count.val + 1
          tool_list_response_with_header(
            id,
            if list_count.val == 1 {
              "Old"
            } else {
              "New"
            },
          )
        } else {
          let old = Ref(false)
          for key, _ in request.headers {
            if key.equal_ignore_ascii_case("Mcp-Param-Old") {
              old.val = true
            }
          }
          if old.val {
            Json::object({
              "jsonrpc": Json::string("2.0"),
              "id": id,
              "error": Json::object({
                "code": Json::number(-32020.0, repr="-32020"),
                "message": Json::string("stale schema"),
              }),
            }).stringify()
          } else {
            Json::object({
              "jsonrpc": Json::string("2.0"),
              "id": id,
              "result": Json::object({
                "resultType": Json::string("complete"),
                "content": Json::array([]),
              }),
            }).stringify()
          }
        }
        ignore(conn.write(response))
        conn.end_response()
      })
    })
    let url = "http://localhost:\{port}/refresh-cache"
    ignore(http_mcp_list_tools(url~, headers=Map([])))
    for _ in 0..<2 {
      ignore(
        http_mcp_call_tool(url~, headers=Map([]), tool_name="search", arguments={
          "region": "x",
        }),
      )
    }
  })
  inspect(
    methods.join(","),
    content="server/discover,tools/list,server/discover,tools/call,tools/list,tools/call,server/discover,tools/call",
  )
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "native http: refreshes tool list after TTL expires" {
  let requests = Ref(0)
  @async.with_task_group(group => {
    let server = @async_http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr.port()
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(allow_failure=true, (_request, body, conn) => {
        requests.val = requests.val + 1
        let msg = @json.parse(body.read_all().text())
        let rpc_method = rpc_method_from_json(msg)
        let id = rpc_id_from_json(msg)
        conn.send_response(200, "OK", extra_headers={
          "content-type": "application/json",
        })
        if rpc_method == "server/discover" {
          ignore(
            conn.write(
              Json::object({
                "jsonrpc": Json::string("2.0"),
                "id": id,
                "result": Json::object({
                  "resultType": Json::string("complete"),
                  "supportedVersions": Json::array([Json::string("2026-07-28")]),
                }),
              }).stringify(),
            ),
          )
        } else {
          ignore(conn.write(short_lived_tool_list_response(id)))
        }
        conn.end_response()
      })
    })
    let url = "http://localhost:\{port}/expiring-cache"
    ignore(http_mcp_list_tools(url~, headers=Map([])))
    ignore(http_mcp_list_tools(url~, headers=Map([])))
    inspect(requests.val, content="2")
    @async.sleep(30)
    ignore(http_mcp_list_tools(url~, headers=Map([])))
    inspect(requests.val, content="4")
  })
}

///|
fn rpc_method_from_json(msg : Json) -> String {
  match msg {
    Object(obj) =>
      match obj.get("method") {
        Some(String(value)) => value
        _ => ""
      }
    _ => ""
  }
}

///|
fn rpc_id_from_json(msg : Json) -> Json {
  match msg {
    Object(obj) => obj.get("id").unwrap_or(Json::number(1.0, repr="1"))
    _ => Json::number(1.0, repr="1")
  }
}

///|
fn discover_response(id : Json) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": id,
    "result": Json::object({
      "resultType": Json::string("complete"),
      "supportedVersions": Json::array([Json::string("2026-07-28")]),
    }),
  }).stringify()
}

///|
fn tool_list_response_with_header(id : Json, header_name : String) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": id,
    "result": Json::object({
      "resultType": Json::string("complete"),
      "tools": Json::array([
        Json::object({
          "name": Json::string("search"),
          "inputSchema": Json::object({
            "type": Json::string("object"),
            "properties": Json::object({
              "region": Json::object({
                "type": Json::string("string"),
                "x-mcp-header": Json::string(header_name),
              }),
            }),
          }),
        }),
      ]),
      "ttlMs": Json::number(60000.0, repr="60000"),
      "cacheScope": Json::string("private"),
    }),
  }).stringify()
}

///|
fn short_lived_tool_list_response(id : Json) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": id,
    "result": Json::object({
      "resultType": Json::string("complete"),
      "tools": Json::array([]),
      "ttlMs": Json::number(10.0, repr="10"),
      "cacheScope": Json::string("private"),
    }),
  }).stringify()
}

///|
fn tool_list_response(id : Json, cache_scope~ : String) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": id,
    "result": Json::object({
      "resultType": Json::string("complete"),
      "tools": Json::array([
        Json::object({
          "name": Json::string("search"),
          "inputSchema": Json::empty_object(),
        }),
      ]),
      "ttlMs": Json::number(60000.0, repr="60000"),
      "cacheScope": Json::string(cache_scope),
    }),
  }).stringify()
}
