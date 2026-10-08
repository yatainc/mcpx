///|
async fn run_call(
  command : @tool_cli.CallCommand,
  home : String,
  config_home : String?,
  stdin_json? : String? = None,
) -> String {
  match command.url {
    Some(url) =>
      return @tool_cli.call_http(command, url~, headers=Map([]), stdin_json~)
    None => ()
  }
  let paths = @app_paths.mcpx_app_paths(home, config_home~)
  let config = @storage.load_mcpx_config_or_empty(paths.servers_config)
  let server = match config.servers.get(command.server) {
    Some(value) => value
    None => return error_result("server not found: " + command.server)
  }
  let server = match resolve_runtime_server(server, paths.env_file) {
    Ok(value) => value
    Err(message) => return error_result(message)
  }
  match server.transport {
    Stdio =>
      if is_keep_alive_server(server) {
        @tool_cli.call_daemon(command, server, home, config_home, stdin_json~)
      } else {
        @tool_cli.call_stdio(command, server, stdin_json~)
      }
    Http => {
      let url = match server.url {
        Some(value) => value
        None => return error_result("server has no url: " + command.server)
      }
      let headers = match
        call_headers_with_cached_auth(
          server_name=command.server,
          server_url=url,
          server~,
          credentials_path=paths.credentials_file,
        ) {
        Ok(value) => value
        Err(message) => return error_result(message)
      }
      @tool_cli.call_http(
        command,
        url~,
        headers~,
        server=Some(server),
        mode=@config.effective_connection_mode(server),
        stdin_json~,
      )
    }
  }
}
