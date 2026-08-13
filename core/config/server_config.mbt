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
  {
    kind: ServerAuthKind::OAuth,
    client_id,
    client_secret,
    metadata_url,
    scopes,
  }
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

///|
fn resolve_server_lifecycle(
  server : McpServerConfig,
  runtime_env : Map[String, String],
) -> ServerLifecycle? {
  let candidates = lifecycle_candidates(server)
  if lifecycle_override_matches(runtime_env, "MCPX_KEEPALIVE", candidates) {
    return Some(server_lifecycle(ServerLifecycleMode::KeepAlive))
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
        Some(server_lifecycle(ServerLifecycleMode::Ephemeral))
      } else if candidates.any(default_keep_alive_name) {
        Some(server_lifecycle(ServerLifecycleMode::KeepAlive))
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
    ServerTransport::Http => None
    ServerTransport::Stdio => {
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
    ServerTransport::Http => false
    ServerTransport::Stdio =>
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

///|
fn resolve_auth_env(
  auth : ServerAuthConfig,
  env : Map[String, String],
) -> Result[ServerAuthConfig, EnvTemplateError] {
  let client_id = match resolve_optional_template(auth.client_id, env) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let client_secret = match resolve_optional_template(auth.client_secret, env) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let metadata_url = match resolve_optional_template(auth.metadata_url, env) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({
    kind: auth.kind,
    client_id,
    client_secret,
    metadata_url,
    scopes: auth.scopes,
  })
}

///|
fn resolve_optional_template(
  value : String?,
  env : Map[String, String],
) -> Result[String?, EnvTemplateError] {
  match value {
    None => Ok(None)
    Some(template) => {
      let resolved = resolve_env_template(template, env) catch {
        error => return Err(error)
      }
      Ok(Some(resolved))
    }
  }
}

///|
fn resolve_string_array(
  values : Array[String],
  env : Map[String, String],
) -> Result[Array[String], EnvTemplateError] {
  let resolved = []
  for value in values {
    let next = resolve_env_template(value, env) catch {
      error => return Err(error)
    }
    resolved.push(next)
  }
  Ok(resolved)
}

///|
fn resolve_string_map(
  values : Map[String, String],
  env : Map[String, String],
) -> Result[Map[String, String], EnvTemplateError] {
  let resolved = Map([], capacity=values.length())
  for key, value in values {
    let next = resolve_env_template(value, env) catch {
      error => return Err(error)
    }
    resolved[key] = next
  }
  Ok(resolved)
}

///|
fn decode_server_config(
  name : String,
  json : Json,
) -> McpServerConfig raise ConfigDecodeError {
  let obj = expect_object(json, "server")
  {
    name,
    transport: decode_transport(
      optional_string(obj.get("transport"), "transport"),
    ),
    url: optional_string(obj.get("url"), "url"),
    command: optional_string(obj.get("command"), "command"),
    args: optional_string_array(obj.get("args"), "args"),
    env: optional_string_map(obj.get("env"), "env"),
    cwd: optional_string(obj.get("cwd"), "cwd"),
    headers: optional_string_map(obj.get("headers"), "headers"),
    auth: optional_auth(obj.get("auth")),
    protocol_mode: optional_protocol_mode(obj.get("protocol")),
    lifecycle: optional_lifecycle(obj.get("lifecycle")),
    allowed_tools: optional_string_array(
      obj.get("allowedTools"),
      "allowedTools",
    ),
    disabled_tools: optional_string_array(
      obj.get("disabledTools"),
      "disabledTools",
    ),
    description: optional_string(obj.get("description"), "description"),
  }
}

///|
fn decode_transport(value : String?) -> ServerTransport raise ConfigDecodeError {
  match value {
    Some("stdio") => ServerTransport::Stdio
    Some("http") | None => ServerTransport::Http
    Some(other) =>
      raise ConfigDecodeError::InvalidConfigJson(
        "unsupported transport: " + other,
      )
  }
}

///|
pub fn effective_connection_mode(server : McpServerConfig) -> McpConnectionMode {
  match server.protocol_mode {
    Some(mode) => mode
    None =>
      match server.transport {
        Http => McpConnectionMode::Auto
        Stdio => McpConnectionMode::Stateful
      }
  }
}

///|
fn optional_protocol_mode(
  json : Json?,
) -> McpConnectionMode? raise ConfigDecodeError {
  match json {
    None | Some(Null) => None
    Some(Object(obj)) =>
      match expect_string(obj.get("mode"), "protocol.mode") {
        "auto" => Some(McpConnectionMode::Auto)
        "stateful" => Some(McpConnectionMode::Stateful)
        "stateless" => Some(McpConnectionMode::Stateless)
        other =>
          raise ConfigDecodeError::InvalidConfigJson(
            "unsupported protocol mode: " + other,
          )
      }
    _ => raise ConfigDecodeError::InvalidConfigJson("protocol must be object")
  }
}

///|
fn optional_lifecycle(json : Json?) -> ServerLifecycle? raise ConfigDecodeError {
  match json {
    None | Some(Null) => None
    Some(String(value)) => Some(decode_lifecycle_mode(value, "lifecycle"))
    Some(Object(obj)) => {
      let mode = match expect_string(obj.get("mode"), "lifecycle.mode") {
        "keep-alive" => ServerLifecycleMode::KeepAlive
        "ephemeral" => ServerLifecycleMode::Ephemeral
        other =>
          raise ConfigDecodeError::InvalidConfigJson(
            "unsupported lifecycle mode: " + other,
          )
      }
      let timeout = optional_positive_int(
        obj.get("idleTimeoutMs"),
        "idleTimeoutMs",
      )
      Some(server_lifecycle(mode, idle_timeout_ms=timeout))
    }
    _ =>
      raise ConfigDecodeError::InvalidConfigJson(
        "lifecycle must be string or object",
      )
  }
}

///|
fn decode_lifecycle_mode(
  value : String,
  field : String,
) -> ServerLifecycle raise ConfigDecodeError {
  match value {
    "keep-alive" => server_lifecycle(ServerLifecycleMode::KeepAlive)
    "ephemeral" => server_lifecycle(ServerLifecycleMode::Ephemeral)
    other =>
      raise ConfigDecodeError::InvalidConfigJson(
        "unsupported " + field + ": " + other,
      )
  }
}

///|
fn optional_positive_int(
  json : Json?,
  field : String,
) -> Int? raise ConfigDecodeError {
  match json {
    None | Some(Null) => None
    Some(Number(value, ..)) if value.trunc() == value && value > 0.0 =>
      Some(value.to_int())
    _ =>
      raise ConfigDecodeError::InvalidConfigJson(
        field + " must be positive integer",
      )
  }
}

///|
fn optional_auth(json : Json?) -> ServerAuthConfig? raise ConfigDecodeError {
  match json {
    None | Some(Null) => None
    Some(value) => {
      let obj = expect_object(value, "auth")
      let kind = match expect_string(obj.get("type"), "auth.type") {
        "oauth" => ServerAuthKind::OAuth
        other =>
          raise ConfigDecodeError::InvalidConfigJson(
            "unsupported auth type: " + other,
          )
      }
      Some({
        kind,
        client_id: optional_string(obj.get("clientId"), "clientId"),
        client_secret: optional_string(obj.get("clientSecret"), "clientSecret"),
        metadata_url: optional_string(obj.get("metadataUrl"), "metadataUrl"),
        scopes: optional_string_array(obj.get("scopes"), "scopes"),
      })
    }
  }
}

///|
fn expect_object(
  json : Json,
  context : String,
) -> Map[String, Json] raise ConfigDecodeError {
  match json {
    Object(obj) => obj
    _ => raise ConfigDecodeError::InvalidConfigJson(context + " must be object")
  }
}

///|
fn expect_object_option(
  json : Json?,
  field : String,
) -> Map[String, Json] raise ConfigDecodeError {
  match json {
    Some(Object(obj)) => obj
    _ => raise ConfigDecodeError::InvalidConfigJson(field + " must be object")
  }
}

///|
fn expect_string(
  json : Json?,
  field : String,
) -> String raise ConfigDecodeError {
  match json {
    Some(String(value)) => value
    _ => raise ConfigDecodeError::InvalidConfigJson(field + " must be string")
  }
}

///|
fn optional_string(
  json : Json?,
  field : String,
) -> String? raise ConfigDecodeError {
  match json {
    None | Some(Null) => None
    Some(String(value)) => Some(value)
    _ => raise ConfigDecodeError::InvalidConfigJson(field + " must be string")
  }
}

///|
fn optional_string_array(
  json : Json?,
  field : String,
) -> Array[String] raise ConfigDecodeError {
  match json {
    None | Some(Null) => []
    Some(Array(values)) => {
      let result = []
      for value in values {
        match value {
          String(text) => result.push(text)
          _ =>
            raise ConfigDecodeError::InvalidConfigJson(
              field + " must contain strings",
            )
        }
      }
      result
    }
    _ => raise ConfigDecodeError::InvalidConfigJson(field + " must be array")
  }
}

///|
fn optional_string_map(
  json : Json?,
  field : String,
) -> Map[String, String] raise ConfigDecodeError {
  match json {
    None | Some(Null) => Map([])
    Some(Object(obj)) => {
      let result = Map([], capacity=obj.length())
      for key, value in obj {
        match value {
          String(text) => result[key] = text
          _ =>
            raise ConfigDecodeError::InvalidConfigJson(
              field + " values must be strings",
            )
        }
      }
      result
    }
    _ => raise ConfigDecodeError::InvalidConfigJson(field + " must be object")
  }
}

///|
pub fn empty_mcpx_config() -> McpxConfig {
  { servers: Map([]) }
}

///|
pub fn put_server_config(
  config : McpxConfig,
  server : McpServerConfig,
) -> McpxConfig {
  let servers = config.servers.copy()
  servers[server.name] = server
  { servers, }
}

///|
pub fn put_remote_mcp_server(
  config : McpxConfig,
  name~ : String,
  url~ : String,
) -> McpxConfig {
  put_server_config(
    config,
    mcp_server_config(name~, transport=ServerTransport::Http, url=Some(url)),
  )
}

///|
pub impl ToJson for McpxConfig with fn to_json(self) {
  let obj = Map([])
  let servers_obj = Map([], capacity=self.servers.length())
  for name, server in self.servers {
    servers_obj[name] = server.to_json()
  }
  obj["mcpServers"] = Json::object(servers_obj)
  Json::object(obj)
}

///|
pub impl ToJson for McpServerConfig with fn to_json(self) {
  let obj = Map([])
  obj["transport"] = Json::string(server_transport_to_string(self.transport))
  match self.url {
    Some(url) => obj["url"] = Json::string(url)
    None => ()
  }
  match self.command {
    Some(command) => obj["command"] = Json::string(command)
    None => ()
  }
  if !self.args.is_empty() {
    obj["args"] = Json::array(self.args.map(Json::string))
  }
  if self.env.length() > 0 {
    obj["env"] = string_map_to_json(self.env)
  }
  match self.cwd {
    Some(cwd) => obj["cwd"] = Json::string(cwd)
    None => ()
  }
  if self.headers.length() > 0 {
    obj["headers"] = string_map_to_json(self.headers)
  }
  if !self.allowed_tools.is_empty() {
    obj["allowedTools"] = Json::array(self.allowed_tools.map(Json::string))
  }
  if !self.disabled_tools.is_empty() {
    obj["disabledTools"] = Json::array(self.disabled_tools.map(Json::string))
  }
  match self.auth {
    Some(auth) => obj["auth"] = auth.to_json()
    None => ()
  }
  match self.protocol_mode {
    Some(mode) =>
      obj["protocol"] = Json::object({
        "mode": Json::string(connection_mode_to_string(mode)),
      })
    None => ()
  }
  match self.lifecycle {
    Some(lifecycle) => obj["lifecycle"] = lifecycle.to_json()
    None => ()
  }
  match self.description {
    Some(description) => obj["description"] = Json::string(description)
    None => ()
  }
  Json::object(obj)
}

///|
pub impl ToJson for ServerLifecycle with fn to_json(self) {
  match (self.mode, self.idle_timeout_ms) {
    (KeepAlive, None) => Json::string("keep-alive")
    (Ephemeral, None) => Json::string("ephemeral")
    _ => {
      let obj = Map([])
      obj["mode"] = Json::string(server_lifecycle_mode_to_string(self.mode))
      match self.idle_timeout_ms {
        Some(value) => obj["idleTimeoutMs"] = json_int(value)
        None => ()
      }
      Json::object(obj)
    }
  }
}

///|
pub impl ToJson for ServerAuthConfig with fn to_json(self) {
  let obj = Map([])
  obj["type"] = Json::string(server_auth_kind_to_string(self.kind))
  match self.client_id {
    Some(value) => obj["clientId"] = Json::string(value)
    None => ()
  }
  match self.client_secret {
    Some(value) => obj["clientSecret"] = Json::string(value)
    None => ()
  }
  match self.metadata_url {
    Some(value) => obj["metadataUrl"] = Json::string(value)
    None => ()
  }
  if !self.scopes.is_empty() {
    obj["scopes"] = Json::array(self.scopes.map(Json::string))
  }
  Json::object(obj)
}

///|
fn server_transport_to_string(transport : ServerTransport) -> String {
  match transport {
    Stdio => "stdio"
    Http => "http"
  }
}

///|
fn connection_mode_to_string(mode : McpConnectionMode) -> String {
  match mode {
    Auto => "auto"
    Stateful => "stateful"
    Stateless => "stateless"
  }
}

///|
fn server_lifecycle_mode_to_string(mode : ServerLifecycleMode) -> String {
  match mode {
    KeepAlive => "keep-alive"
    Ephemeral => "ephemeral"
  }
}

///|
fn json_int(value : Int) -> Json {
  Json::number(Double::from_int(value), repr=value.to_string())
}

///|
fn server_auth_kind_to_string(kind : ServerAuthKind) -> String {
  match kind {
    OAuth => "oauth"
  }
}

///|
fn string_map_to_json(map : Map[String, String]) -> Json {
  let obj = Map([], capacity=map.length())
  for key, value in map {
    obj[key] = Json::string(value)
  }
  Json::object(obj)
}
