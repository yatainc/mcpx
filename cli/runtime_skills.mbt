///|
async fn run_retrieval(
  command : @skill_cli.Command,
  home : String,
  config_home : String?,
  cwd : String,
) -> String {
  let (_, url) = target_server_url(command.target)
  if url is Some(url) {
    return @skill_cli.run_http(command, url~, headers=Map([]))
  }
  let paths = @app_paths.mcpx_app_paths(home, config_home~)
  let servers = load_servers(paths, cwd)
  guard servers.get(command.target) is Some(binding) else {
    raise @skill_cli.RetrievalError("server not found: " + command.target)
  }
  let origin = binding.identity()
  let server = binding.server
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
  let server = prepare_server(binding, paths.env_file)
  if server.transport is Stdio && is_keep_alive_server(server) {
    raise @skill_cli.RetrievalError(
      "retrieval requires an ephemeral stdio target",
    )
  }
  match server.transport {
    Stdio => @skill_cli.run_stdio(command, server, origin~)
    Http => {
      guard server.url is Some(url) else {
        raise @skill_cli.RetrievalError("server has no url: " + command.target)
      }
      let headers = match
        call_headers_with_cached_auth(
          server_name=origin,
          server_url=url,
          server~,
          credentials_path=paths.credentials_file,
        ) {
        Ok(headers) => headers
        Err(message) => raise @skill_cli.RetrievalError(message)
      }
      @skill_cli.run_http(command, url~, headers~, origin~)
    }
  }
}
