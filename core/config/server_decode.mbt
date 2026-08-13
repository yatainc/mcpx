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
    Some("stdio") => Stdio
    Some("http") | None => Http
    Some(other) => raise InvalidConfigJson("unsupported transport: " + other)
  }
}

///|
pub fn effective_connection_mode(server : McpServerConfig) -> McpConnectionMode {
  match server.protocol_mode {
    Some(mode) => mode
    None =>
      match server.transport {
        Http => Auto
        Stdio => Stateful
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
        "auto" => Some(Auto)
        "stateful" => Some(Stateful)
        "stateless" => Some(Stateless)
        other => raise InvalidConfigJson("unsupported protocol mode: " + other)
      }
    _ => raise InvalidConfigJson("protocol must be object")
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
        "ephemeral" => Ephemeral
        other => raise InvalidConfigJson("unsupported lifecycle mode: " + other)
      }
      let timeout = optional_positive_int(
        obj.get("idleTimeoutMs"),
        "idleTimeoutMs",
      )
      Some(server_lifecycle(mode, idle_timeout_ms=timeout))
    }
    _ => raise InvalidConfigJson("lifecycle must be string or object")
  }
}

///|
fn decode_lifecycle_mode(
  value : String,
  field : String,
) -> ServerLifecycle raise ConfigDecodeError {
  match value {
    "keep-alive" => server_lifecycle(KeepAlive)
    "ephemeral" => server_lifecycle(Ephemeral)
    other => raise InvalidConfigJson("unsupported " + field + ": " + other)
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
    _ => raise InvalidConfigJson(field + " must be positive integer")
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
        other => raise InvalidConfigJson("unsupported auth type: " + other)
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
    _ => raise InvalidConfigJson(context + " must be object")
  }
}

///|
fn expect_object_option(
  json : Json?,
  field : String,
) -> Map[String, Json] raise ConfigDecodeError {
  match json {
    Some(Object(obj)) => obj
    _ => raise InvalidConfigJson(field + " must be object")
  }
}

///|
fn expect_string(
  json : Json?,
  field : String,
) -> String raise ConfigDecodeError {
  match json {
    Some(String(value)) => value
    _ => raise InvalidConfigJson(field + " must be string")
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
    _ => raise InvalidConfigJson(field + " must be string")
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
          _ => raise InvalidConfigJson(field + " must contain strings")
        }
      }
      result
    }
    _ => raise InvalidConfigJson(field + " must be array")
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
          _ => raise InvalidConfigJson(field + " values must be strings")
        }
      }
      result
    }
    _ => raise InvalidConfigJson(field + " must be object")
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
    mcp_server_config(name~, transport=Http, url=Some(url)),
  )
}
