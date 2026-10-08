///|
fn resolve_call_arguments(
  command : CallCommand,
  stdin_json? : String? = None,
) -> Result[Json, String] {
  match (command.arguments_json, stdin_json) {
    (None, None) => Ok(Json::empty_object())
    (Some(text), _) | (None, Some(text)) => {
      let text = text.trim()
      if text.is_empty() {
        Ok(Json::empty_object())
      } else {
        Ok(
          @json.parse(text) catch {
            _ => return Err("invalid JSON arguments")
          },
        )
      }
    }
  }
}

///|
fn disabled_tool_result(server : String, tool : String) -> String {
  "Error: tool is disabled by config: " + server + "/" + tool
}

///|
pub async fn call_http(
  command : CallCommand,
  url~ : String,
  headers~ : Map[String, String],
  server? : @config.McpServerConfig? = None,
  mode? : @config.McpConnectionMode = Auto,
  stdin_json? : String? = None,
) -> String {
  match server {
    Some(server) if !@config.is_tool_allowed(server, command.tool) =>
      return disabled_tool_result(command.server, command.tool)
    _ => ()
  }
  let arguments = match resolve_call_arguments(command, stdin_json~) {
    Ok(value) => value
    Err(message) => return error_result(message)
  }
  let result = @mcp_http.http_mcp_call_tool(
    url~,
    headers~,
    tool_name=command.tool,
    arguments~,
    mode~,
  ) catch {
    error => return mcp_http_error_result(command.server, error)
  }
  call_result(result)
}

///|
pub async fn call_stdio(
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
  let arguments = match resolve_call_arguments(command, stdin_json~) {
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
  call_result(result)
}

///|
pub async fn call_daemon(
  command : CallCommand,
  server : @config.McpServerConfig,
  home : String,
  config_home : String?,
  stdin_json? : String? = None,
) -> String {
  if !@config.is_tool_allowed(server, command.tool) {
    return disabled_tool_result(command.server, command.tool)
  }
  let arguments = match resolve_call_arguments(command, stdin_json~) {
    Ok(value) => value
    Err(message) => return error_result(message)
  }
  let result = @mcpx_daemon.daemon_call_tool(
    home~,
    config_home~,
    server_name=command.server,
    server~,
    tool_name=command.tool,
    arguments~,
  ) catch {
    error =>
      return error_result(
        "mcp daemon error: " + @mcpx_daemon.describe_mcpx_daemon_error(error),
      )
  }
  call_result(result)
}
