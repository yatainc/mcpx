///|
fn resolve_runtime_server(
  server : @config.McpServerConfig,
  env_file : String,
) -> Result[@config.McpServerConfig, String] {
  let env = match load_mcpx_env(env_file) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  match @config.resolve_server_env(server, env) {
    Ok(value) => Ok(value)
    Err(error) => Err(error.to_string())
  }
}

///|
fn is_keep_alive_server(server : @config.McpServerConfig) -> Bool {
  match server.lifecycle {
    Some({ mode: KeepAlive, .. }) => true
    _ => false
  }
}

///|
fn current_time_seconds() -> Int {
  (@env.now() / 1000UL).to_int()
}

///|

///|
fn load_mcpx_env(path : String) -> Result[Map[String, String], String] {
  let file_env = if @fs.path_exists(path) {
    let text = @fs.read_file_to_string(path) catch {
      _ => return Err("failed to read .env")
    }
    match @config.parse_dotenv(text) {
      Ok(value) => value
      Err(InvalidDotenvLine(line_number, line)) =>
        return Err("invalid .env line " + line_number.to_string() + ": " + line)
    }
  } else {
    Map([])
  }
  Ok(@config.merge_env(file_env, @env.get_env_vars()))
}
