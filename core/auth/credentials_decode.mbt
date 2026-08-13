///|
pub fn decode_credentials_file(
  json : Json,
) -> CredentialsFile raise CredentialsError {
  let obj = expect_object(json, "credentials file")
  let version = expect_int(obj.get("version"), "version")
  let entries_json = expect_object_option(obj.get("entries"), "entries")
  let entries = Map([], capacity=entries_json.length())
  for key, value in entries_json {
    entries[key] = decode_credentials_entry(value)
  }
  let pending_oauth_json = optional_object_map(obj.get("pendingOAuth"))
  let pending_oauth = Map([], capacity=pending_oauth_json.length())
  for key, value in pending_oauth_json {
    pending_oauth[key] = decode_pending_oauth_flow(value)
  }
  { version, entries, pending_oauth }
}

///|
fn decode_credentials_entry(
  json : Json,
) -> CredentialsEntry raise CredentialsError {
  let obj = expect_object(json, "credentials entry")
  {
    server_name: expect_string(obj.get("serverName"), "serverName"),
    server_url: optional_string(obj.get("serverUrl"), "serverUrl"),
    client_info: optional_client_info(obj.get("clientInfo")),
    tokens: decode_tokens(obj.get("tokens")),
    updated_at: expect_string(obj.get("updatedAt"), "updatedAt"),
  }
}

///|
fn optional_client_info(
  json : Json?,
) -> OAuthClientInfo? raise CredentialsError {
  match json {
    None | Some(Null) => None
    Some(value) => {
      let obj = expect_object(value, "clientInfo")
      Some({ client_id: expect_string(obj.get("client_id"), "client_id") })
    }
  }
}

///|
fn decode_pending_oauth_flow(
  json : Json,
) -> PendingOAuthFlow raise CredentialsError {
  let obj = expect_object(json, "pending OAuth flow")
  {
    server_name: expect_string(obj.get("serverName"), "serverName"),
    server_url: optional_string(obj.get("serverUrl"), "serverUrl"),
    client_info: decode_client_secret_info(obj.get("clientInfo")),
    token_endpoint: expect_string(obj.get("tokenEndpoint"), "tokenEndpoint"),
    authorization_issuer: optional_string(
      obj.get("authorizationIssuer"),
      "authorizationIssuer",
    ),
    require_authorization_issuer: optional_bool(
      obj.get("requireAuthorizationIssuer"),
      "requireAuthorizationIssuer",
    ),
    redirect_uri: expect_string(obj.get("redirectUri"), "redirectUri"),
    code_verifier: expect_string(obj.get("codeVerifier"), "codeVerifier"),
    state: expect_string(obj.get("state"), "state"),
    created_at: expect_string(obj.get("createdAt"), "createdAt"),
  }
}

///|
fn decode_client_secret_info(
  json : Json?,
) -> OAuthClientSecretInfo raise CredentialsError {
  let obj = expect_object_option(json, "clientInfo")
  {
    client_id: expect_string(obj.get("client_id"), "client_id"),
    client_secret: optional_string(obj.get("client_secret"), "client_secret"),
  }
}

///|
fn decode_tokens(json : Json?) -> OAuthTokens raise CredentialsError {
  let obj = expect_object_option(json, "tokens")
  oauth_tokens(
    expect_string(obj.get("access_token"), "access_token"),
    refresh_token=optional_string(obj.get("refresh_token"), "refresh_token"),
    expires_at=optional_int(obj.get("expires_at"), "expires_at"),
  )
}

///|
fn expect_object(
  json : Json,
  context : String,
) -> Map[String, Json] raise CredentialsError {
  match json {
    Object(obj) => obj
    _ => raise InvalidCredentialsJson(context + " must be object")
  }
}

///|
fn expect_object_option(
  json : Json?,
  field : String,
) -> Map[String, Json] raise CredentialsError {
  match json {
    Some(Object(obj)) => obj
    _ => raise InvalidCredentialsJson(field + " must be object")
  }
}

///|
fn optional_object_map(
  json : Json?,
) -> Map[String, Json] raise CredentialsError {
  match json {
    None | Some(Null) => Map([])
    Some(Object(obj)) => obj
    _ => raise InvalidCredentialsJson("pendingOAuth must be object")
  }
}

///|
fn expect_string(json : Json?, field : String) -> String raise CredentialsError {
  match json {
    Some(String(value)) => value
    _ => raise InvalidCredentialsJson(field + " must be string")
  }
}

///|
fn optional_string(
  json : Json?,
  field : String,
) -> String? raise CredentialsError {
  match json {
    None | Some(Null) => None
    Some(String(value)) => Some(value)
    _ => raise InvalidCredentialsJson(field + " must be string")
  }
}

///|
fn optional_bool(json : Json?, field : String) -> Bool raise CredentialsError {
  match json {
    None | Some(Null) | Some(False) => false
    Some(True) => true
    _ => raise InvalidCredentialsJson(field + " must be bool")
  }
}

///|
fn expect_int(json : Json?, field : String) -> Int raise CredentialsError {
  match json {
    Some(Number(value, ..)) if value.trunc() == value => value.to_int()
    _ => raise InvalidCredentialsJson(field + " must be int")
  }
}

///|
fn optional_int(json : Json?, field : String) -> Int? raise CredentialsError {
  match json {
    None | Some(Null) => None
    Some(Number(value, ..)) if value.trunc() == value => Some(value.to_int())
    _ => raise InvalidCredentialsJson(field + " must be int")
  }
}

///|
fn json_int(value : Int) -> Json {
  Json::number(Double::from_int(value), repr=value.to_string())
}
