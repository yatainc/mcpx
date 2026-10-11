///|
async fn run_info(
  command : @tool_cli.InfoCommand,
  home : String,
  config_home : String?,
  cwd : String,
) -> String {
  let target = match command.server {
    None => {
      let paths = @app_paths.mcpx_app_paths(home, config_home~)
      return servers_result(load_servers(paths, cwd), paths.config_dir)
    }
    Some(value) => value
  }
  match command.url {
    Some(url) =>
      return @tool_cli.info_http(
        server_name=target,
        url~,
        headers=Map([]),
        tool=command.tool,
        filter_server=None,
      )
    None => ()
  }
  let paths = @app_paths.mcpx_app_paths(home, config_home~)
  let servers = load_servers(paths, cwd)
  let binding = match servers.get(target) {
    Some(value) => value
    None => return error_result("server not found: " + target)
  }
  let server = prepare_server(binding, paths.env_file)
  match server.transport {
    Stdio =>
      if is_keep_alive_server(server) {
        @tool_cli.info_daemon(
          target,
          server,
          home,
          config_home,
          command.tool,
          server_id=binding.identity(),
        )
      } else {
        @tool_cli.info_stdio(target, server, command.tool)
      }
    Http => {
      let url = match server.url {
        Some(value) => value
        None => return error_result("server has no url: " + target)
      }
      let headers = match
        call_headers_with_cached_auth(
          server_name=binding.identity(),
          server_url=url,
          server~,
          credentials_path=paths.credentials_file,
        ) {
        Ok(value) => value
        Err(message) => return error_result(message)
      }
      @tool_cli.info_http(
        server_name=target,
        url~,
        headers~,
        tool=command.tool,
        filter_server=Some(server),
        mode=@config.effective_connection_mode(server),
      )
    }
  }
}
