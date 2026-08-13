///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: auth no-browser starts OAuth and replaces old pending flow" {
  let home = "/tmp/mcpx-runtime-auth-static-test/home"
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
    let metadata_url = "http://localhost:\{port}/metadata"
    @storage.save_credentials_file(
      paths.credentials_file,
      @auth.put_pending_oauth_flow(
        @auth.empty_credentials_file(),
        @auth.pending_oauth_flow(
          server_name="github",
          server_url=Some("http://localhost:\{port}/mcp"),
          client_id="old-client",
          token_endpoint="http://localhost:\{port}/token",
          redirect_uri="http://127.0.0.1:8765/callback",
          code_verifier="old-verifier",
          state="old-state",
          created_at="100",
        ),
      ),
    )
    @storage.save_mcpx_config_file(
      paths.servers_config,
      @config.put_server_config(
        @config.empty_mcpx_config(),
        @config.mcp_server_config(
          name="github",
          transport=@config.ServerTransport::Http,
          url=Some("http://localhost:\{port}/mcp"),
          auth=Some(
            @config.oauth_server_auth(
              client_id=Some("client-1"),
              metadata_url=Some(metadata_url),
              scopes=["repo", "read:user"],
            ),
          ),
        ),
      ),
    )
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(allow_failure=true, (_request, _body, conn) => {
        conn.send_response(200, "OK", extra_headers={
          "content-type": "application/json",
        })
        conn
        ..write(
          Json::object({
            "authorization_endpoint": Json::string(
              "http://localhost:\{port}/authorize",
            ),
            "token_endpoint": Json::string("http://localhost:\{port}/token"),
            "scopes_supported": Json::array([
              Json::string("repo"),
              Json::string("read:user"),
            ]),
          }).stringify(),
        )
        .end_response()
      })
    })
    let result = run_mcpx_args_async(
      ["auth", "github", "--no-browser", "--json"],
      home~,
    )
    inspect(result.contains("\"status\":\"ok\""), content="true")
    inspect(result.contains("\"action\":\"auth\""), content="true")
    inspect(result.contains("client_id=client-1"), content="true")
    inspect(result.contains("code_challenge_method=S256"), content="true")
    inspect(result.contains("scope=repo%20read%3Auser"), content="true")
    inspect(result.contains("code_verifier"), content="false")
    let state = json_string_field(result, "state")
    let credentials = @storage.load_credentials_file_or_empty(
      paths.credentials_file,
    )
    inspect(credentials.pending_oauth.length(), content="1")
    inspect(
      credentials.pending_oauth.contains("github|old-state"),
      content="false",
    )
    let pending = @auth.find_pending_oauth_flow(
      credentials,
      server_name="github",
      state~,
    )
    @debug.debug_inspect(
      pending.map(flow => {
        (flow.client_info.client_id, flow.code_verifier.length())
      }),
      content=(
        #|Some(("client-1", 43))
      ),
    )
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: auth no-browser json supports dynamic client registration" {
  let home = "/tmp/mcpx-runtime-auth-dynamic-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.servers_config) catch {
    _ => ()
  }
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr.port()
    let metadata_url = "http://localhost:\{port}/metadata"
    let registration_url = "http://localhost:\{port}/register"
    @storage.save_mcpx_config_file(
      paths.servers_config,
      @config.put_server_config(
        @config.empty_mcpx_config(),
        @config.mcp_server_config(
          name="github",
          transport=@config.ServerTransport::Http,
          url=Some("http://localhost:\{port}/mcp"),
          auth=Some(@config.oauth_server_auth(metadata_url=Some(metadata_url))),
        ),
      ),
    )
    let seen_registration_body = []
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
              "token_endpoint": Json::string("http://localhost:\{port}/token"),
              "registration_endpoint": Json::string(registration_url),
            }).stringify(),
          )
          .end_response()
        } else {
          seen_registration_body.push(body.read_all().text())
          conn.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
          })
          conn
          ..write(
            Json::object({ "client_id": Json::string("dyn-1") }).stringify(),
          )
          .end_response()
        }
      })
    })
    let result = run_mcpx_args_async(
      ["auth", "github", "--no-browser", "--json"],
      home~,
    )
    inspect(result.contains("client_id=dyn-1"), content="true")
    inspect(
      seen_registration_body.join(",").contains("\"client_name\":\"mcpx\""),
      content="true",
    )
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: auth discovers OAuth when metadata URL is absent" {
  let home = "/tmp/mcpx-runtime-auth-discovery-test/home"
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
    let resource_url = "http://localhost:\{port}/resource"
    let issuer = "http://localhost:\{port}/tenant-a"
    @storage.save_mcpx_config_file(
      paths.servers_config,
      @config.put_server_config(
        @config.empty_mcpx_config(),
        @config.mcp_server_config(
          name="github",
          transport=@config.ServerTransport::Http,
          url=Some("http://localhost:\{port}/mcp"),
          auth=Some(@config.oauth_server_auth(client_id=Some("client-1"))),
        ),
      ),
    )
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(allow_failure=true, (request, _body, conn) => {
        if request.path == "/mcp" {
          conn.send_response(401, "Unauthorized", extra_headers={
            "WWW-Authenticate": "Bearer realm=\"mcp\", resource_metadata=\"\{resource_url}\"",
          })
          conn.end_response()
        } else if request.path == "/resource" {
          conn.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
          })
          conn
          ..write(
            Json::object({
              "authorization_servers": Json::array([Json::string(issuer)]),
            }).stringify(),
          )
          .end_response()
        } else if request.path ==
          "/.well-known/oauth-authorization-server/tenant-a" {
          conn.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
          })
          conn
          ..write(
            Json::object({
              "authorization_endpoint": Json::string(
                "http://localhost:\{port}/authorize",
              ),
              "token_endpoint": Json::string("http://localhost:\{port}/token"),
            }).stringify(),
          )
          .end_response()
        } else {
          conn.send_response(404, "Not Found")
          conn.end_response()
        }
      })
    })
    let result = run_mcpx_args_async(
      ["auth", "github", "--no-browser", "--json"],
      home~,
    )
    inspect(result.contains("\"status\":\"ok\""), content="true")
    inspect(result.contains("client_id=client-1"), content="true")
    inspect(result.contains("scope="), content="false")
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: auth discovery supports lowercase header and root issuer" {
  let home = "/tmp/mcpx-runtime-auth-discovery-root-test/home"
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
    let resource_url = "http://localhost:\{port}/resource"
    let issuer = "http://localhost:\{port}"
    @storage.save_mcpx_config_file(
      paths.servers_config,
      @config.put_server_config(
        @config.empty_mcpx_config(),
        @config.mcp_server_config(
          name="github",
          transport=@config.ServerTransport::Http,
          url=Some("http://localhost:\{port}/mcp"),
          auth=Some(@config.oauth_server_auth(client_id=Some("client-1"))),
        ),
      ),
    )
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(allow_failure=true, (request, _body, conn) => {
        if request.path == "/mcp" {
          conn.send_response(401, "Unauthorized", extra_headers={
            "www-authenticate": "Bearer realm=\"mcp\", resource_metadata=\"\{resource_url}\"",
          })
          conn.end_response()
        } else if request.path == "/resource" {
          conn.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
          })
          conn
          ..write(
            Json::object({
              "authorization_servers": Json::array([Json::string(issuer)]),
            }).stringify(),
          )
          .end_response()
        } else if request.path == "/.well-known/oauth-authorization-server" {
          conn.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
          })
          conn
          ..write(
            Json::object({
              "authorization_endpoint": Json::string(
                "http://localhost:\{port}/authorize",
              ),
              "token_endpoint": Json::string("http://localhost:\{port}/token"),
            }).stringify(),
          )
          .end_response()
        } else {
          conn.send_response(404, "Not Found")
          conn.end_response()
        }
      })
    })
    let result = run_mcpx_args_async(
      ["auth", "github", "--no-browser", "--json"],
      home~,
    )
    inspect(result.contains("\"status\":\"ok\""), content="true")
    inspect(result.contains("client_id=client-1"), content="true")
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: auth discovery fails when challenge has no resource metadata" {
  let home = "/tmp/mcpx-runtime-auth-discovery-no-resource-test/home"
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
    @storage.save_mcpx_config_file(
      paths.servers_config,
      @config.put_server_config(
        @config.empty_mcpx_config(),
        @config.mcp_server_config(
          name="github",
          transport=@config.ServerTransport::Http,
          url=Some("http://localhost:\{port}/mcp"),
          auth=Some(@config.oauth_server_auth(client_id=Some("client-1"))),
        ),
      ),
    )
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(allow_failure=true, (_request, _body, conn) => {
        conn.send_response(401, "Unauthorized", extra_headers={
          "WWW-Authenticate": "Bearer realm=\"mcp\"",
        })
        conn.end_response()
      })
    })
    let result = run_mcpx_args_async(
      ["auth", "github", "--no-browser", "--json"],
      home~,
    )
    inspect(
      result.contains("OAuth metadata URL is required: github"),
      content="true",
    )
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: auth config is required before OAuth discovery" {
  let home = "/tmp/mcpx-runtime-auth-discovery-no-auth-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.servers_config) catch {
    _ => ()
  }
  @fs.remove_file(paths.credentials_file) catch {
    _ => ()
  }
  @storage.save_mcpx_config_file(
    paths.servers_config,
    @config.put_server_config(
      @config.empty_mcpx_config(),
      @config.mcp_server_config(
        name="github",
        transport=@config.ServerTransport::Http,
        url=Some("http://localhost:1/mcp"),
      ),
    ),
  )
  let result = run_mcpx_args_async(
    ["auth", "github", "--no-browser", "--json"],
    home~,
  )
  inspect(result.contains("server has no OAuth config: github"), content="true")
}

///|
async test "mcpx runtime: auth rejects mismatched RFC 9207 issuer before exchange" {
  let home = "/tmp/mcpx-runtime-auth-issuer-mismatch-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.credentials_file) catch {
    _ => ()
  }
  @storage.save_credentials_file(
    paths.credentials_file,
    @auth.put_pending_oauth_flow(
      @auth.empty_credentials_file(),
      @auth.pending_oauth_flow(
        server_name="github",
        client_id="client-1",
        token_endpoint="http://127.0.0.1:1/token",
        authorization_issuer=Some("https://auth.example"),
        require_authorization_issuer=true,
        redirect_uri="http://127.0.0.1:8765/callback",
        code_verifier="verifier-1",
        state="state-1",
        created_at="1000",
      ),
    ),
  )
  let result = run_mcpx_args_async(
    [
      "auth", "github", "--code", "code-1", "--state", "state-1", "--iss", "https://attacker.example",
    ],
    home~,
  )
  inspect(
    result.contains("OAuth authorization response issuer mismatch"),
    content="true",
  )
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: auth code exchange stores credentials and removes pending flow" {
  let home = "/tmp/mcpx-runtime-auth-exchange-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.credentials_file) catch {
    _ => ()
  }
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr.port()
    let token_endpoint = "http://localhost:\{port}/token"
    @storage.save_credentials_file(
      paths.credentials_file,
      @auth.put_pending_oauth_flow(
        @auth.put_pending_oauth_flow(
          @auth.put_credentials_entry(
            @auth.empty_credentials_file(),
            "github|old-client",
            @auth.credentials_entry(
              server_name="github",
              server_url=Some("http://localhost:\{port}/mcp"),
              client_id=Some("old-client"),
              access_token="old-token",
              refresh_token=Some("old-refresh-token"),
              updated_at="100",
            ),
          ),
          @auth.pending_oauth_flow(
            server_name="github",
            server_url=Some("http://localhost:\{port}/mcp"),
            client_id="old-client",
            token_endpoint~,
            redirect_uri="http://127.0.0.1:8765/callback",
            code_verifier="old-verifier",
            state="old-state",
            created_at="1000",
          ),
        ),
        @auth.pending_oauth_flow(
          server_name="github",
          server_url=Some("http://localhost:\{port}/mcp"),
          client_id="client-1",
          token_endpoint~,
          redirect_uri="http://127.0.0.1:8765/callback",
          code_verifier="verifier-1",
          state="state-1",
          created_at="1000",
        ),
      ),
    )
    let seen_body = []
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(allow_failure=true, (_request, body, conn) => {
        seen_body.push(body.read_all().text())
        conn.send_response(200, "OK", extra_headers={
          "content-type": "application/json",
        })
        conn
        ..write(
          Json::object({
            "access_token": Json::string("access-1"),
            "refresh_token": Json::string("refresh-1"),
            "expires_in": Json::number(3600.0, repr="3600"),
          }).stringify(),
        )
        .end_response()
      })
    })
    let result = run_mcpx_args_async(
      ["auth", "github", "--code", "code-1", "--state", "state-1"],
      home~,
    )
    inspect(result, content="Auth complete: github")
    inspect(
      seen_body.join(","),
      content=(
        #|grant_type=authorization_code&client_id=client-1&code=code-1&redirect_uri=http%3A%2F%2F127.0.0.1%3A8765%2Fcallback&code_verifier=verifier-1
      ),
    )
    let credentials = @storage.load_credentials_file_or_empty(
      paths.credentials_file,
    )
    inspect(
      credentials.to_json().stringify().contains("\"pendingOAuth\""),
      content="false",
    )
    inspect(credentials.entries.length(), content="1")
    inspect(credentials.entries.contains("github|old-client"), content="false")
    inspect(credentials.entries.contains("github|client-1"), content="true")
    let entry = @auth.find_credentials_entry(
      credentials,
      server_name="github",
      server_url=Some("http://localhost:\{port}/mcp"),
    )
    @debug.debug_inspect(
      entry.map(value => (value.tokens.access_token, value.tokens.refresh_token)),
      content=(
        #|Some(("access-1", Some("refresh-1")))
      ),
    )
  })
}

///|
fn json_string_field(text : String, field : String) -> String {
  let parsed = @json.parse(text) catch { _ => return "" }
  match parsed {
    Object(obj) =>
      match obj.get(field) {
        Some(String(value)) => value
        _ => ""
      }
    _ => ""
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: interactive auth uses browser callback listener" {
  let home = "/tmp/mcpx-runtime-auth-interactive-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.servers_config) catch {
    _ => ()
  }
  @fs.remove_file(paths.credentials_file) catch {
    _ => ()
  }
  let old_browser = @env.get_env_var("MCPX_BROWSER")
  @env.set_env_var("MCPX_BROWSER", "fetch")
  defer (match old_browser {
    Some(value) => @env.set_env_var("MCPX_BROWSER", value)
    None => @env.unset_env_var("MCPX_BROWSER")
  })
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let port = server.addr.port()
    let metadata_url = "http://localhost:\{port}/metadata"
    @storage.save_mcpx_config_file(
      paths.servers_config,
      @config.put_server_config(
        @config.empty_mcpx_config(),
        @config.mcp_server_config(
          name="github",
          transport=@config.ServerTransport::Http,
          url=Some("http://localhost:\{port}/mcp"),
          auth=Some(
            @config.oauth_server_auth(
              client_id=Some("client-1"),
              metadata_url=Some(metadata_url),
              scopes=["repo", "read:user"],
            ),
          ),
        ),
      ),
    )
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
              "token_endpoint": Json::string("http://localhost:\{port}/token"),
            }).stringify(),
          )
          .end_response()
        } else if request.path.has_prefix("/authorize?") {
          let redirect_uri = test_query_param(request.path, "redirect_uri")
          let state = test_query_param(request.path, "state")
          ignore(@http.get(redirect_uri + "?code=code-1&state=" + state))
          conn.send_response(200, "OK")
          conn.end_response()
        } else if request.path == "/token" {
          ignore(body.read_all().text())
          conn.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
          })
          conn
          ..write(
            Json::object({
              "access_token": Json::string("token-1"),
              "token_type": Json::string("Bearer"),
              "expires_in": Json::number(3600.0, repr="3600"),
            }).stringify(),
          )
          .end_response()
        } else {
          conn.send_response(404, "Not Found")
          conn.end_response()
        }
      })
    })
    let result = run_mcpx_args_async(["auth", "github"], home~)
    inspect(result, content="Auth complete: github")
    let credentials = @storage.load_credentials_file_or_empty(
      paths.credentials_file,
    )
    inspect(credentials.entries.length(), content="1")
  })
}

///|
fn test_query_param(path : String, name : String) -> String {
  match path.split_once("?") {
    None => ""
    Some((_prefix, query)) =>
      for part in query.to_owned().split("&") {
        match part.to_owned().split_once("=") {
          Some((key, value)) if key.to_owned() == name =>
            break test_url_decode(value.to_owned())
          _ => ()
        }
      } nobreak {
        ""
      }
  }
}

///|
fn test_url_decode(value : String) -> String {
  value
  .replace_all(old="%3A", new=":")
  .replace_all(old="%2F", new="/")
  .replace_all(old="%2f", new="/")
  .replace_all(old="%20", new=" ")
  .replace_all(old="%3D", new="=")
  .replace_all(old="%26", new="&")
}
