///|
fn daemon_pool_key(
  server_name : String,
  server : @config.McpServerConfig,
) -> String {
  server_name +
  ":" +
  server_public_identity_json(server_name, server).stringify()
}

///|
fn server_public_identity_json(
  server_name : String,
  server : @config.McpServerConfig,
) -> Json {
  let obj = Map([])
  obj["server"] = Json::string(server_name)
  obj["transport"] = match server.transport {
    Http => "http"
    Stdio => "stdio"
  }
  match server.url {
    Some(url) => obj["url"] = Json::string(public_url_identity(url))
    None => ()
  }
  match server.command {
    Some(command) => obj["command"] = Json::string(command)
    None => ()
  }
  if !server.args.is_empty() {
    obj["args"] = server.args.to_json()
  }
  match server.cwd {
    Some(cwd) => obj["cwd"] = Json::string(cwd)
    None => ()
  }
  let header_names = sorted_string_map_keys(server.headers)
  if !header_names.is_empty() {
    obj["headerNames"] = header_names.to_json()
  }
  let env_names = sorted_string_map_keys(server.env)
  if !env_names.is_empty() {
    obj["envNames"] = env_names.to_json()
  }
  if !server.allowed_tools.is_empty() {
    obj["allowedTools"] = server.allowed_tools.to_json()
  }
  if !server.disabled_tools.is_empty() {
    obj["disabledTools"] = server.disabled_tools.to_json()
  }
  match server.auth {
    Some(auth) => obj["auth"] = auth_public_identity_json(auth)
    None => ()
  }
  match server.lifecycle {
    Some(lifecycle) =>
      obj["lifecycle"] = lifecycle_public_identity_json(lifecycle)
    None => ()
  }
  Json::object(obj)
}

///|
fn auth_public_identity_json(auth : @config.ServerAuthConfig) -> Json {
  let obj = Map([])
  obj["type"] = Json::string("oauth")
  match auth.client_id {
    Some(value) => obj["clientId"] = Json::string(value)
    None => ()
  }
  match auth.metadata_url {
    Some(value) => obj["metadataUrl"] = Json::string(value)
    None => ()
  }
  if !auth.scopes.is_empty() {
    obj["scopes"] = auth.scopes.to_json()
  }
  Json::object(obj)
}

///|
fn lifecycle_public_identity_json(lifecycle : @config.ServerLifecycle) -> Json {
  let obj : Map[String, Json] = Map([])
  obj["mode"] = match lifecycle.mode {
    KeepAlive => "keep-alive"
    Ephemeral => "ephemeral"
  }
  match lifecycle.idle_timeout_ms {
    Some(value) => obj["idleTimeoutMs"] = value.to_json()
    None => ()
  }
  Json::object(obj)
}

///|
fn sorted_string_map_keys(values : Map[String, String]) -> Array[String] {
  let keys = []
  for key, _ in values {
    keys.push(key)
  }
  keys.sort()
  keys
}

///|
fn public_url_identity(url : String) -> String {
  strip_url_userinfo(before_url_delimiter(before_url_delimiter(url, "#"), "?"))
}

///|
fn before_url_delimiter(value : String, delimiter : String) -> String {
  match value.split_once(delimiter) {
    Some((before, _)) => before.to_owned()
    None => value
  }
}

///|
fn strip_url_userinfo(url : String) -> String {
  match url.split_once("://") {
    Some((scheme, rest)) => {
      let scheme_text = scheme.to_owned()
      let rest_text = rest.to_owned()
      match rest_text.split_once("/") {
        Some((authority, path)) =>
          scheme_text +
          "://" +
          strip_authority_userinfo(authority.to_owned()) +
          "/" +
          path.to_owned()
        None => scheme_text + "://" + strip_authority_userinfo(rest_text)
      }
    }
    None => url
  }
}

///|
fn strip_authority_userinfo(authority : String) -> String {
  match authority.rev_split_once("@") {
    Some((_, host)) => host.to_owned()
    None => authority
  }
}
