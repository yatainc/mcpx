///|
async fn run_retrieval(
  command : @skill_cli.Command,
  home : String,
  config_home : String?,
) -> String {
  let (_, url) = target_server_url(command.target)
  if url is Some(url) {
    return @skill_cli.run_http(command, url~, headers=Map([]))
  }
  let paths = @app_paths.mcpx_app_paths(home, config_home~)
  let config = @storage.load_mcpx_config_or_empty(paths.servers_config)
  guard config.servers.get(command.target) is Some(server) else {
    raise @skill_cli.RetrievalError("server not found: " + command.target)
  }
  if server.protocol_mode == Some(Stateful) {
    raise @skill_cli.RetrievalError(
      "retrieval requires MCP 2026-07-28, not stateful mode",
    )
  }
  if server.transport is Stdio && is_keep_alive_server(server) {
    raise @skill_cli.RetrievalError(
      "retrieval requires an ephemeral stdio target",
    )
  }
  let server = match resolve_runtime_server(server, paths.env_file) {
    Ok(server) => server
    Err(message) => raise @skill_cli.RetrievalError(message)
  }
  match server.transport {
    Stdio => @skill_cli.run_stdio(command, server)
    Http => {
      guard server.url is Some(url) else {
        raise @skill_cli.RetrievalError("server has no url: " + command.target)
      }
      let headers = match
        call_headers_with_cached_auth(
          server_name=command.target,
          server_url=url,
          server~,
          credentials_path=paths.credentials_file,
        ) {
        Ok(headers) => headers
        Err(message) => raise @skill_cli.RetrievalError(message)
      }
      @skill_cli.run_http(command, url~, headers~)
    }
  }
}
