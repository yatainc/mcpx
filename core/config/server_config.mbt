///|
pub struct McpxConfig {
  servers : Map[String, McpServerConfig]
} derive(Debug)

///|
pub struct McpServerConfig {
  name : String
  transport : ServerTransport
  url : String?
  command : String?
  args : Array[String]
  env : Map[String, String]
  cwd : String?
  headers : Map[String, String]
  auth : ServerAuthConfig?
  protocol_mode : McpConnectionMode?
  lifecycle : ServerLifecycle?
  allowed_tools : Array[String]
  disabled_tools : Array[String]
  description : String?
} derive(Debug)

///|
pub(all) enum ServerTransport {
  Stdio
  Http
} derive(Debug)

///|
pub(all) enum ServerAuthKind {
  OAuth
} derive(Debug)

///|
pub(all) enum McpConnectionMode {
  Auto
  Stateful
  Stateless
} derive(Debug, Eq)

///|
pub struct ServerAuthConfig {
  kind : ServerAuthKind
  client_id : String?
  client_secret : String?
  metadata_url : String?
  scopes : Array[String]
} derive(Debug)

///|
pub(all) enum ServerLifecycleMode {
  KeepAlive
  Ephemeral
} derive(Debug)

///|
pub struct ServerLifecycle {
  mode : ServerLifecycleMode
  idle_timeout_ms : Int?
} derive(Debug)

///|
suberror ConfigDecodeError {
  InvalidConfigJson(String)
} derive(Debug)

///|
pub fn mcp_server_config(
  name~ : String,
  transport~ : ServerTransport,
  url? : String? = None,
  command? : String? = None,
  args? : Array[String] = [],
  env? : Map[String, String] = Map([]),
  cwd? : String? = None,
  headers? : Map[String, String] = Map([]),
  auth? : ServerAuthConfig? = None,
  protocol_mode? : McpConnectionMode? = None,
  lifecycle? : ServerLifecycle? = None,
  allowed_tools? : Array[String] = [],
  disabled_tools? : Array[String] = [],
  description? : String? = None,
) -> McpServerConfig {
  {
    name,
    transport,
    url,
    command,
    args,
    env,
    cwd,
    headers,
    auth,
    protocol_mode,
    lifecycle,
    allowed_tools,
    disabled_tools,
    description,
  }
}

///|
pub fn server_lifecycle(
  mode : ServerLifecycleMode,
  idle_timeout_ms? : Int? = None,
) -> ServerLifecycle {
  { mode, idle_timeout_ms }
}

///|
pub fn oauth_server_auth(
  client_id? : String? = None,
  client_secret? : String? = None,
  metadata_url? : String? = None,
  scopes? : Array[String] = [],
) -> ServerAuthConfig {
  { kind: OAuth, client_id, client_secret, metadata_url, scopes }
}

///|
pub fn decode_mcpx_config(json : Json) -> McpxConfig raise ConfigDecodeError {
  let obj = expect_object(json, "config")
  let servers_json = expect_object_option(obj.get("mcpServers"), "mcpServers")
  let servers = Map([], capacity=servers_json.length())
  for name, server_json in servers_json {
    servers[name] = decode_server_config(name, server_json)
  }
  { servers, }
}

///|
pub fn resolve_server_env(
  server : McpServerConfig,
  env : Map[String, String],
) -> Result[McpServerConfig, EnvTemplateError] {
  let headers = Map([], capacity=server.headers.length())
  for key, value in server.headers {
    let resolved = resolve_env_template(value, env) catch {
      error => return Err(error)
    }
    headers[key] = resolved
  }
  let auth = match server.auth {
    None => None
    Some(value) =>
      match resolve_auth_env(value, env) {
        Ok(resolved) => Some(resolved)
        Err(error) => return Err(error)
      }
  }
  let url = match resolve_optional_template(server.url, env) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let command = match resolve_optional_template(server.command, env) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let args = match resolve_string_array(server.args, env) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let resolved_env = match resolve_string_map(server.env, env) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let cwd = match resolve_optional_template(server.cwd, env) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let lifecycle = resolve_server_lifecycle(server, env)
  Ok({
    name: server.name,
    transport: server.transport,
    url,
    command,
    args,
    env: resolved_env,
    cwd,
    headers,
    auth,
    protocol_mode: server.protocol_mode,
    lifecycle,
    allowed_tools: server.allowed_tools,
    disabled_tools: server.disabled_tools,
    description: server.description,
  })
}

///|
pub fn is_tool_allowed(server : McpServerConfig, tool_name : String) -> Bool {
  let allowed = if server.allowed_tools.is_empty() {
    true
  } else {
    server.allowed_tools.any(pattern => glob_match(pattern, tool_name))
  }
  if !allowed {
    false
  } else {
    !server.disabled_tools.any(pattern => glob_match(pattern, tool_name))
  }
}

///|
pub fn[T] filter_tools(
  server : McpServerConfig,
  tools : Array[T],
  name_of : (T) -> String,
) -> Array[T] {
  tools.filter(tool => is_tool_allowed(server, name_of(tool)))
}

///|
pub fn glob_match(pattern : String, text : String) -> Bool {
  // Greedy wildcard matcher for '*' and '?'.
  // Avoids exponential backtracking from recursive glob matching.
  let pattern_chars = pattern.to_array()
  let text_chars = text.to_array()
  let mut p = 0
  let mut t = 0
  let mut star = -1
  let mut match_after_star = 0
  while t < text_chars.length() {
    if p < pattern_chars.length() &&
      (pattern_chars[p] == '?' || pattern_chars[p] == text_chars[t]) {
      p = p + 1
      t = t + 1
    } else if p < pattern_chars.length() && pattern_chars[p] == '*' {
      star = p
      p = p + 1
      match_after_star = t
    } else if star >= 0 {
      p = star + 1
      match_after_star = match_after_star + 1
      t = match_after_star
    } else {
      return false
    }
  }
  while p < pattern_chars.length() && pattern_chars[p] == '*' {
    p = p + 1
  }
  p == pattern_chars.length()
}
