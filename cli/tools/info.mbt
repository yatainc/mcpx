///|
pub async fn info_http(
  server_name~ : String,
  url~ : String,
  headers~ : Map[String, String],
  tool~ : String?,
  filter_server~ : @config.McpServerConfig?,
  mode? : @config.McpConnectionMode = Auto,
) -> String {
  let tools = @mcp_http.http_mcp_list_tools(url~, headers~, mode~) catch {
    error => return mcp_http_error_result(server_name, error)
  }
  info_tools_result(server_name, tools, tool, filter_server~)
}

///|
pub async fn info_stdio(
  server_name : String,
  server : @config.McpServerConfig,
  tool : String?,
) -> String {
  let executable = match server.command {
    Some(value) => value
    None => return error_result("server has no command: " + server_name)
  }
  let tools = @mcp_stdio.stdio_mcp_list_tools(
    command=executable,
    args=server.args,
    env=server.env,
    cwd=server.cwd,
    mode=@config.effective_connection_mode(server),
  ) catch {
    _ => return error_result("mcp stdio error")
  }
  info_tools_result(server_name, tools, tool, filter_server=Some(server))
}

///|
pub async fn info_daemon(
  server_name : String,
  server : @config.McpServerConfig,
  home : String,
  config_home : String?,
  tool : String?,
) -> String {
  let tools = @mcpx_daemon.daemon_list_tools(
    home~,
    config_home~,
    server_name~,
    server~,
  ) catch {
    _ => return error_result("mcp daemon error")
  }
  info_tools_result(server_name, tools, tool, filter_server=Some(server))
}
