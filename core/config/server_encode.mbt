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
