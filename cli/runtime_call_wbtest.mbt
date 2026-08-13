///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: call uses configured remote HTTP server" {
  let home = "/tmp/mcpx-runtime-call-test/home"
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
            "Mcp-Session-Id": "sid123",
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
        } else {
          conn.send_response(500, "Unknown")
          conn.end_response()
        }
      })
    })
    let result = run_mcpx_args_async(
      ["call", "github", "search", "{\"q\":\"moonbit\"}"],
      home~,
    )
    inspect(result, content="Result:\n{\"ok\":true}")
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: call can use direct remote URL without config" {
  let home = "/tmp/mcpx-runtime-call-direct-url-test/home"
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
        } else if rpc_method == "tools/call" {
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
        } else {
          conn.send_response(500, "Unknown")
          conn.end_response()
        }
      })
    })
    let result = run_mcpx_args_async(
      ["call", "http://localhost:\{port}/mcp", "search", "{\"q\":\"moonbit\"}"],
      home~,
    )
    inspect(result, content="Result:\n{\"ok\":true}")
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: call resolves headers from .env before HTTP request" {
  let home = "/tmp/mcpx-runtime-call-env-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.servers_config) catch {
    _ => ()
  }
  @fs.remove_file(paths.env_file) catch {
    _ => ()
  }
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr.port()
    @storage.save_mcpx_config_file(
      paths.servers_config,
      @config.put_server_config(
        @config.empty_mcpx_config(),
        @config.mcp_server_config(
          name="github",
          transport=Http,
          url=Some("http://localhost:\{port}/mcp"),
          headers={ "Authorization": "Bearer ${GITHUB_TOKEN}" },
        ),
      ),
    )
    @fs.write_string_to_file(paths.env_file, "GITHUB_TOKEN=file-token\n")
    let seen_auth = []
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
        if rpc_method == "server/discover" {
          conn..send_response(400, "Bad Request").end_response()
        } else if rpc_method == "initialize" {
          conn.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
            "Mcp-Session-Id": "sid-env",
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
          seen_auth.push(request.headers.get("authorization").unwrap_or("none"))
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
        } else {
          conn.send_response(500, "Unknown")
          conn.end_response()
        }
      })
    })
    ignore(
      run_mcpx_args_async(
        ["call", "github", "search", "{\"q\":\"moonbit\"}"],
        home~,
      ),
    )
    inspect(seen_auth.join(","), content="Bearer file-token")
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: call rejects disabled configured tools before connect" {
  let home = "/tmp/mcpx-runtime-call-filter-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.servers_config) catch {
    _ => ()
  }
  @storage.save_mcpx_config_file(
    paths.servers_config,
    @config.put_server_config(
      @config.empty_mcpx_config(),
      @config.mcp_server_config(
        name="github",
        transport=Http,
        url=Some("http://127.0.0.1:1/mcp"),
        allowed_tools=["*"],
        disabled_tools=["delete_*"],
      ),
    ),
  )
  inspect(
    run_mcpx_args_async(["call", "github", "delete_repo"], home~),
    content=(
      #|Error: tool is disabled by config: github/delete_repo
    ),
  )
}

///|
#cfg(all(target="native", not(platform="windows")))
test "mcpx runtime: call arguments can come from stdin when JSON arg omitted" {
  match parse_mcpx_args(["call", "github", "search"]) {
    Ok(Call(command)) =>
      inspect(
        resolve_call_arguments_for_test(
          command,
          stdin_json=Some("{\"q\":\"stdin\"}"),
        ).stringify(),
        content="{\"q\":\"stdin\"}",
      )
    other => @debug.debug_inspect(other, content="UNREACHABLE")
  }
  match parse_mcpx_args(["call", "github", "search", "{\"q\":\"argv\"}"]) {
    Ok(Call(command)) =>
      inspect(
        resolve_call_arguments_for_test(
          command,
          stdin_json=Some("{\"q\":\"stdin\"}"),
        ).stringify(),
        content="{\"q\":\"argv\"}",
      )
    other => @debug.debug_inspect(other, content="UNREACHABLE")
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: call uses cached OAuth bearer from credentials file" {
  let home = "/tmp/mcpx-runtime-call-credentials-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.servers_config) catch {
    _ => ()
  }
  @fs.remove_file(paths.credentials_file) catch {
    _ => ()
  }
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr.port()
    let url = "http://localhost:\{port}/mcp"
    @storage.save_mcpx_config_file(
      paths.servers_config,
      @config.put_server_config(
        @config.empty_mcpx_config(),
        @config.mcp_server_config(
          name="github",
          transport=Http,
          url=Some(url),
          auth=Some(@config.oauth_server_auth()),
        ),
      ),
    )
    @storage.save_credentials_file(
      paths.credentials_file,
      @auth.put_pending_oauth_flow(
        @auth.put_credentials_entry(
          @auth.put_credentials_entry(
            @auth.empty_credentials_file(),
            "github|old-client",
            @auth.credentials_entry(
              server_name="github",
              server_url=Some(url),
              client_id=Some("old-client"),
              access_token="old-token",
              refresh_token=Some("old-refresh-token"),
              updated_at="100",
            ),
          ),
          "github|client-1",
          @auth.credentials_entry(
            server_name="github",
            server_url=Some(url),
            client_id=Some("client-1"),
            access_token="cached-token",
            refresh_token=Some("refresh-token"),
            updated_at="200",
          ),
        ),
        @auth.pending_oauth_flow(
          server_name="github",
          server_url=Some(url),
          client_id="active-client",
          token_endpoint="https://auth.example/token",
          redirect_uri="http://127.0.0.1:8765/callback",
          code_verifier="active-verifier",
          state="active-state",
          created_at="300",
        ),
      ),
    )
    let seen_auth = []
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
        if rpc_method == "server/discover" {
          conn..send_response(400, "Bad Request").end_response()
        } else if rpc_method == "initialize" {
          conn.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
            "Mcp-Session-Id": "sid-credentials",
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
          seen_auth.push(request.headers.get("authorization").unwrap_or("none"))
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
        } else {
          conn.send_response(500, "Unknown")
          conn.end_response()
        }
      })
    })
    ignore(
      run_mcpx_args_async(
        ["call", "github", "search", "{\"q\":\"moonbit\"}"],
        home~,
      ),
    )
    inspect(seen_auth.join(","), content="Bearer cached-token")
    let credentials = @storage.load_credentials_file_or_empty(
      paths.credentials_file,
    )
    inspect(credentials.entries.length(), content="1")
    inspect(credentials.entries.contains("github|old-client"), content="false")
    inspect(credentials.entries.contains("github|client-1"), content="true")
    inspect(credentials.pending_oauth.length(), content="1")
    inspect(
      credentials.pending_oauth.contains("github|active-state"),
      content="true",
    )
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: call returns friendly auth hint on remote 401" {
  let home = "/tmp/mcpx-runtime-call-401-test/home"
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
      server.run_forever(allow_failure=true, (_request, _body, conn) => {
        conn.send_response(401, "Unauthorized", extra_headers={
          "content-type": "application/json",
        })
        conn..write("{\"error\":\"missing token\"}").end_response()
      })
    })
    let result = run_mcpx_args_async(
      ["call", "github", "search", "{\"q\":\"moonbit\"}"],
      home~,
    )
    inspect(
      result,
      content=(
        #|Error: github returned 401 Unauthorized. Authentication is required.
        #|
        #|Try:
        #|  mcpx auth github
        #|  mcpx auth github --no-browser --json
      ),
    )
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: call reports concrete HTTP status errors" {
  let home = "/tmp/mcpx-runtime-call-500-test/home"
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
      server.run_forever(allow_failure=true, (_request, _body, conn) => {
        conn.send_response(500, "Internal Server Error", extra_headers={
          "content-type": "text/plain",
        })
        conn..write("boom").end_response()
      })
    })
    let configured = run_mcpx_args_async(
      ["call", "github", "search", "{\"q\":\"moonbit\"}"],
      home~,
    )
    inspect(configured, content="Error: github returned HTTP 500")
    let direct = run_mcpx_args_async(
      ["call", "http://localhost:\{port}/mcp", "search", "{\"q\":\"moonbit\"}"],
      home~,
    )
    inspect(direct, content="Error: remote returned HTTP 500")
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: call reports MCP protocol errors" {
  let home = "/tmp/mcpx-runtime-call-protocol-error-test/home"
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
      server.run_forever(allow_failure=true, (_request, _body, conn) => {
        conn.send_response(200, "OK", extra_headers={
          "content-type": "application/json",
        })
        conn..write("{\"not\":\"jsonrpc\"}").end_response()
      })
    })
    let result = run_mcpx_args_async(
      ["call", "github", "search", "{\"q\":\"moonbit\"}"],
      home~,
    )
    inspect(result, content="Error: github MCP protocol error")
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: call refreshes near-expiry OAuth token before request" {
  let home = "/tmp/mcpx-runtime-call-refresh-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.servers_config) catch {
    _ => ()
  }
  @fs.remove_file(paths.credentials_file) catch {
    _ => ()
  }
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr.port()
    let mcp_url = "http://localhost:\{port}/mcp"
    let metadata_url = "http://localhost:\{port}/metadata"
    let token_url = "http://localhost:\{port}/token"
    @storage.save_mcpx_config_file(
      paths.servers_config,
      @config.put_server_config(
        @config.empty_mcpx_config(),
        @config.mcp_server_config(
          name="github",
          transport=Http,
          url=Some(mcp_url),
          auth=Some(
            @config.oauth_server_auth(
              client_id=Some("client-1"),
              metadata_url=Some(metadata_url),
            ),
          ),
        ),
      ),
    )
    @storage.save_credentials_file(
      paths.credentials_file,
      @auth.put_pending_oauth_flow(
        @auth.put_credentials_entry(
          @auth.empty_credentials_file(),
          "github|client-1",
          @auth.credentials_entry(
            server_name="github",
            server_url=Some(mcp_url),
            client_id=Some("client-1"),
            access_token="expired-token",
            refresh_token=Some("refresh-token"),
            expires_at=Some(1),
            updated_at="2026-05-16T00:00:00.000Z",
          ),
        ),
        @auth.pending_oauth_flow(
          server_name="github",
          server_url=Some(mcp_url),
          client_id="active-client",
          token_endpoint="https://auth.example/token",
          redirect_uri="http://127.0.0.1:8765/callback",
          code_verifier="active-verifier",
          state="active-state",
          created_at="300",
        ),
      ),
    )
    let seen_auth = []
    let seen_refresh_body = []
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(allow_failure=true, (request, body, conn) => {
        if request.path == "/metadata" {
          conn.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
          })
          conn
          ..write(
            Json::object({
              "authorization_endpoint": Json::string(
                "http://localhost:\{port}/authorize",
              ),
              "token_endpoint": Json::string(token_url),
            }).stringify(),
          )
          .end_response()
        } else if request.path == "/token" {
          seen_refresh_body.push(body.read_all().text())
          conn.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
          })
          conn
          ..write(
            Json::object({
              "access_token": Json::string("refreshed-token"),
              "refresh_token": Json::string("refresh-token-2"),
              "expires_in": Json::number(3600.0, repr="3600"),
            }).stringify(),
          )
          .end_response()
        } else {
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
              "Mcp-Session-Id": "sid-refresh",
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
            seen_auth.push(
              request.headers.get("authorization").unwrap_or("none"),
            )
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
          } else {
            conn.send_response(500, "Unknown")
            conn.end_response()
          }
        }
      })
    })
    let result = run_mcpx_args_async(
      ["call", "github", "search", "{\"q\":\"moonbit\"}"],
      home~,
    )
    inspect(result, content="Result:\n{\"ok\":true}")
    inspect(seen_auth.join(","), content="Bearer refreshed-token")
    inspect(
      seen_refresh_body.join(","),
      content=(
        #|grant_type=refresh_token&client_id=client-1&refresh_token=refresh-token
      ),
    )
    let credentials = @storage.load_credentials_file_or_empty(
      paths.credentials_file,
    )
    inspect(credentials.entries.length(), content="1")
    inspect(credentials.entries.contains("github|client-1"), content="true")
    inspect(credentials.pending_oauth.length(), content="1")
    inspect(
      credentials.pending_oauth.contains("github|active-state"),
      content="true",
    )
  })
}
