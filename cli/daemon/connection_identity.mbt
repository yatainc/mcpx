///|
// Hash the prepared launch, not a lossy/public projection of its configuration.
fn daemon_pool_key(
  server_id : String,
  server : @config.McpServerConfig,
) -> String {
  let keys = server.env.keys().to_array()
  keys.sort()
  let env = keys.map(key => [key, server.env[key]].to_json())
  let mode = match @config.effective_connection_mode(server) {
    Auto => "auto"
    Stateful => "stateful"
    Stateless => "stateless"
  }
  let identity = Json::array([
    server_id.to_json(),
    server.command.to_json(),
    server.args.to_json(),
    server.cwd.to_json(),
    env.to_json(),
    mode.to_json(),
    server_idle_timeout_ms(server).to_json(),
  ]).stringify()
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(identity)))
}
