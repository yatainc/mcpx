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
          ignore(conn.write(tool_list_response(id)))
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
          ignore(conn.write(tool_list_response(id)))
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
fn tool_list_response(id : Json) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": id,
    "result": Json::object({
      "tools": Json::array([
        Json::object({
          "name": Json::string("search"),
          "inputSchema": Json::empty_object(),
        }),
      ]),
    }),
  }).stringify()
}
