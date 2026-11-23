///|
// Hash the prepared launch, not a lossy/public projection of its configuration.
fn daemon_pool_key(
  server_id : String,
  server : @config.McpServerConfig,
) -> String {
  let keys = server.env.keys().to_array()
  keys.sort()
  let env = keys.map(key => Json([key, server.env[key]]))
  let mode = match @config.effective_connection_mode(server) {
    Auto => "auto"
    Stateful => "stateful"
    Stateless => "stateless"
  }
  let identity = Json::array([
    Json(server_id),
    Json(server.command),
    Json(server.args),
    Json(server.cwd),
    Json(env),
    Json(mode),
    Json(server_idle_timeout_ms(server)),
  ]).stringify()
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(identity)))
}
