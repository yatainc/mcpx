///|
async fn run_call(
  command : CallCommand,
  home : String,
  config_home : String?,
  stdin_json? : String? = None,
) -> String {
  match command.url {
    Some(url) => return run_call_url(command, url, headers=Map([]), stdin_json~)
    None => ()
  }
  let paths = @app_paths.mcpx_app_paths(home, config_home~)
  let config = @storage.load_mcpx_config_or_empty(paths.servers_config)
  match config.servers.get(command.server) {
    None => error_result("server not found: " + command.server)
    Some(server) => {
      let resolved_server = match
        resolve_runtime_server(server, paths.env_file) {
        Ok(value) => value
        Err(message) => return error_result(message)
      }
      match resolved_server.transport {
        @config.ServerTransport::Stdio =>
          if is_keep_alive_server(resolved_server) {
            run_call_daemon(
              command,
              resolved_server,
              home,
              config_home,
              stdin_json~,
            )
          } else {
            run_call_stdio(command, resolved_server, stdin_json~)
          }
        @config.ServerTransport::Http =>
          match resolved_server.url {
            None => error_result("server has no url: " + command.server)
            Some(url) => {
              let headers = match
                call_headers_with_cached_auth(
                  server_name=command.server,
                  server_url=url,
                  server=resolved_server,
                  credentials_path=paths.credentials_file,
                ) {
                Ok(value) => value
                Err(message) => return error_result(message)
              }
              if !@config.is_tool_allowed(resolved_server, command.tool) {
                return disabled_tool_result(command.server, command.tool)
              }
              let arguments = match
                parse_call_arguments_with_stdin(command, stdin_json~) {
                Ok(value) => value
                Err(message) => return error_result(message)
              }
              run_call_json(
                server_name=command.server,
                url~,
                headers~,
                tool_name=command.tool,
                arguments~,
                mode=@config.effective_connection_mode(resolved_server),
              )
            }
          }
      }
    }
  }
}

///|
fn resolve_call_arguments(
  command : CallCommand,
  stdin_json? : String? = None,
) -> Result[Json, String] {
  match (command.arguments_json, stdin_json) {
    (Some(text), _) | (None, Some(text)) => {
      let trimmed = text.trim()
      if trimmed.is_empty() {
        Ok(Json::empty_object())
      } else {
        let json = @json.parse(trimmed) catch {
          _ => return Err("invalid JSON arguments")
        }
        Ok(json)
      }
    }
    (None, None) => Ok(Json::empty_object())
  }
}

///|
pub fn resolve_call_arguments_for_test(
  command : CallCommand,
  stdin_json? : String? = None,
) -> Json {
  resolve_call_arguments(command, stdin_json~).unwrap()
}

///|
fn parse_call_arguments_with_stdin(
  command : CallCommand,
  stdin_json? : String? = None,
) -> Result[Json, String] {
  resolve_call_arguments(command, stdin_json~)
}

///|
fn disabled_tool_result(server : String, tool : String) -> String {
  "Error: tool is disabled by config: " + server + "/" + tool
}

///|
async fn run_call_daemon(
  command : CallCommand,
  server : @config.McpServerConfig,
  home : String,
  config_home : String?,
  stdin_json? : String? = None,
) -> String {
  if !@config.is_tool_allowed(server, command.tool) {
    return disabled_tool_result(command.server, command.tool)
  }
  let arguments = match parse_call_arguments_with_stdin(command, stdin_json~) {
    Ok(value) => value
    Err(message) => return error_result(message)
  }
  let result = @mcpx_daemon.daemon_call_tool(
    home~,
    config_home~,
    key=daemon_pool_key(command.server, server),
    server~,
    tool_name=command.tool,
    arguments~,
  ) catch {
    error =>
      return error_result(
        "mcp daemon error: " + @mcpx_daemon.describe_mcpx_daemon_error(error),
      )
  }
  ok_result(result)
}

///|
async fn run_call_stdio(
  command : CallCommand,
  server : @config.McpServerConfig,
  stdin_json? : String? = None,
) -> String {
  let executable = match server.command {
    Some(value) => value
    None => return error_result("server has no command: " + command.server)
  }
  if !@config.is_tool_allowed(server, command.tool) {
    return disabled_tool_result(command.server, command.tool)
  }
  let arguments = match parse_call_arguments_with_stdin(command, stdin_json~) {
    Ok(value) => value
    Err(message) => return error_result(message)
  }
  let result = @mcp_stdio.stdio_mcp_call_tool(
    command=executable,
    args=server.args,
    env=server.env,
    cwd=server.cwd,
    mode=@config.effective_connection_mode(server),
    tool_name=command.tool,
    arguments~,
  ) catch {
    _ => return error_result("mcp stdio error")
  }
  ok_result(result)
}

///|
async fn run_call_url(
  command : CallCommand,
  url : String,
  headers~ : Map[String, String],
  stdin_json? : String? = None,
) -> String {
  let arguments = match parse_call_arguments_with_stdin(command, stdin_json~) {
    Ok(value) => value
    Err(message) => return error_result(message)
  }
  run_call_json(
    server_name=command.server,
    url~,
    headers~,
    tool_name=command.tool,
    arguments~,
  )
}

///|
async fn run_call_json(
  server_name~ : String,
  url~ : String,
  headers~ : Map[String, String],
  tool_name~ : String,
  arguments~ : Json,
  mode? : @config.McpConnectionMode = @config.McpConnectionMode::Auto,
) -> String {
  let result = @mcp_http.http_mcp_call_tool(
    url~,
    headers~,
    tool_name~,
    arguments~,
    mode~,
  ) catch {
    error => return mcp_http_error_result(server_name, error)
  }
  ok_result(result)
}

///|
fn ok_result(result : Json) -> String {
  match mcp_text_content(result) {
    Some(text) => text
    None => "Result:\n" + result.stringify()
  }
}

///|
fn mcp_text_content(result : Json) -> String? {
  match result {
    Object(obj) =>
      match obj.get("content") {
        Some(Array(items)) => {
          let parts = []
          for item in items {
            match item {
              Object(content) =>
                if content.get("type") == Some(Json::string("text")) {
                  match content.get("text") {
                    Some(String(text)) => parts.push(text)
                    _ => ()
                  }
                }
              _ => ()
            }
          }
          if parts.is_empty() {
            None
          } else {
            Some(parts.join("\n\n"))
          }
        }
        _ => None
      }
    _ => None
  }
}
