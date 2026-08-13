///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: info uses configured remote HTTP server" {
  let home = "/tmp/mcpx-runtime-list-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.servers_config) catch {
    _ => ()
  }
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr.port()
    @storage.save_mcpx_config_file(
      paths.servers_config,
      @config.put_remote_mcp_server(
        @config.empty_mcpx_config(),
        name="github",
        url="http://localhost:\{port}/mcp",
      ),
    )
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
    let result = run_mcpx_args_async(["info", "github"], home~)
    inspect(
      result,
      content=(
        #|Tools
        #|  search()
        #|    Search things
      ),
    )
    let schema = run_mcpx_args_async(["info", "github", "search"], home~)
    inspect(
      schema,
      content=(
        #|Tool: github/search
        #|
        #|Search things
        #|
        #|Arguments:
        #|  (none)
      ),
    )
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: info without target lists configured servers" {
  let home = "/tmp/mcpx-runtime-info-servers-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.servers_config) catch {
    _ => ()
  }
  let config = @config.put_server_config(
    @config.empty_mcpx_config(),
    @config.mcp_server_config(
      name="github",
      transport=@config.ServerTransport::Http,
      url=Some("https://mcp.github.com/mcp"),
      description=Some("GitHub Issues, PRs, and code search\nMore details"),
    ),
  )
  @storage.save_mcpx_config_file(
    paths.servers_config,
    @config.put_server_config(
      config,
      @config.mcp_server_config(
        name="very-long-server-name",
        transport=@config.ServerTransport::Http,
        url=Some("https://example.com/mcp"),
        description=Some(
          "This description is intentionally longer than sixty characters total",
        ),
      ),
    ),
  )
  inspect(
    run_mcpx_args_async(["info"], home~),
    content=(
      #|Servers:
      #|  github                 GitHub Issues, PRs, and code search
      #|  very-long-server-name  This description is intentionally longer than sixty chara...
    ),
  )
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: info can use direct remote URL without config" {
  let home = "/tmp/mcpx-runtime-list-direct-url-test/home"
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
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
    let result = run_mcpx_args_async(
      ["info", "http://localhost:\{port}/mcp"],
      home~,
    )
    inspect(
      result,
      content=(
        #|Tools
        #|  search()
      ),
    )
  })
}
