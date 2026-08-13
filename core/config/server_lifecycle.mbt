///|
fn resolve_server_lifecycle(
  server : McpServerConfig,
  runtime_env : Map[String, String],
) -> ServerLifecycle? {
  let candidates = lifecycle_candidates(server)
  if lifecycle_override_matches(runtime_env, "MCPX_KEEPALIVE", candidates) {
    return Some(server_lifecycle(KeepAlive))
  }
  if lifecycle_override_matches(
      runtime_env, "MCPX_DISABLE_KEEPALIVE", candidates,
    ) ||
    lifecycle_override_matches(runtime_env, "MCPX_NO_KEEPALIVE", candidates) {
    return None
  }
  match server.lifecycle {
    Some(value) => Some(value)
    None =>
      if command_requires_dynamic_chrome_port(server) {
        Some(server_lifecycle(Ephemeral))
      } else if candidates.any(default_keep_alive_name) {
        Some(server_lifecycle(KeepAlive))
      } else {
        None
      }
  }
}

///|
fn lifecycle_candidates(server : McpServerConfig) -> Array[String] {
  let values = [server.name.to_lower()]
  match canonical_keep_alive_name(server) {
    Some(value) =>
      if values.contains(value) {
        values
      } else {
        values.push(value)
        values
      }
    None => values
  }
}

///|
fn lifecycle_override_matches(
  runtime_env : Map[String, String],
  key : String,
  candidates : Array[String],
) -> Bool {
  match runtime_env.get(key) {
    None => false
    Some(value) => {
      for token in comma_list(value) {
        if token == "*" || candidates.contains(token) {
          return true
        }
      }
      false
    }
  }
}

///|
fn comma_list(value : String) -> Array[String] {
  let result = []
  for token in value.split(",") {
    let normalized = token.trim().to_owned().to_lower()
    if !normalized.is_empty() {
      result.push(normalized)
    }
  }
  result
}

///|
fn default_keep_alive_name(name : String) -> Bool {
  name == "chrome-devtools" || name == "mobile-mcp" || name == "playwright"
}

///|
fn canonical_keep_alive_name(server : McpServerConfig) -> String? {
  match server.transport {
    Http => None
    Stdio => {
      let tokens = lifecycle_tokens(server)
      if tokens.any(token => token.contains("chrome-devtools-mcp")) {
        Some("chrome-devtools")
      } else if tokens.any(token => {
          token.contains("@mobilenext/mobile-mcp") ||
          token.contains("mobile-mcp")
        }) {
        Some("mobile-mcp")
      } else if tokens.any(token => {
          token.contains("@playwright/mcp") || token.contains("playwright/mcp")
        }) {
        Some("playwright")
      } else {
        None
      }
    }
  }
}

///|
fn command_requires_dynamic_chrome_port(server : McpServerConfig) -> Bool {
  match server.transport {
    Http => false
    Stdio =>
      lifecycle_raw_tokens(server).any(token => {
        token.contains("${CHROME_DEVTOOLS_URL}") ||
        token.contains("$env:CHROME_DEVTOOLS_URL")
      })
  }
}

///|
fn lifecycle_tokens(server : McpServerConfig) -> Array[String] {
  lifecycle_raw_tokens(server).map(token => token.to_lower())
}

///|
fn lifecycle_raw_tokens(server : McpServerConfig) -> Array[String] {
  let tokens = []
  match server.command {
    Some(command) => tokens.push(command)
    None => ()
  }
  for arg in server.args {
    tokens.push(arg)
  }
  tokens
}
