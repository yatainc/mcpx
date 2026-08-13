///|
pub struct OAuthMetadata {
  authorization_endpoint : String
  token_endpoint : String
  registration_endpoint : String?
  scopes_supported : Array[String]
  issuer : String?
  authorization_response_iss_parameter_supported : Bool
} derive(Debug)

///|
pub fn oauth_metadata(
  authorization_endpoint~ : String,
  token_endpoint~ : String,
  registration_endpoint? : String? = None,
  scopes_supported? : Array[String] = [],
  issuer? : String? = None,
  authorization_response_iss_parameter_supported? : Bool = false,
) -> OAuthMetadata {
  {
    authorization_endpoint,
    token_endpoint,
    registration_endpoint,
    scopes_supported,
    issuer,
    authorization_response_iss_parameter_supported,
  }
}

///|
pub fn select_oauth_scopes(
  _metadata : OAuthMetadata,
  requested_scopes~ : Array[String],
) -> Array[String] {
  requested_scopes
}

///|
pub fn oauth_authorization_url(
  metadata : OAuthMetadata,
  client_id~ : String,
  redirect_uri~ : String,
  state~ : String,
  code_challenge~ : String,
  scopes~ : Array[String],
) -> String {
  let params = [
    query_pair("response_type", "code"),
    query_pair("client_id", client_id),
    query_pair("redirect_uri", redirect_uri),
    query_pair("code_challenge", code_challenge),
    query_pair("code_challenge_method", "S256"),
    query_pair("state", state),
  ]
  if !scopes.is_empty() {
    params.push(query_pair("scope", scopes.join(" ")))
  }
  metadata.authorization_endpoint + "?" + params.join("&")
}

///|
pub fn validate_authorization_response_issuer(
  metadata : OAuthMetadata,
  response_issuer : String?,
) -> Result[Unit, OAuthPlanError] {
  match (metadata.issuer, response_issuer) {
    (Some(expected), Some(actual)) if actual == expected => Ok(())
    (Some(_), Some(_)) =>
      Err(InvalidAuthorizationResponse("authorization response iss mismatch"))
    (Some(_), None) if metadata.authorization_response_iss_parameter_supported =>
      Err(InvalidAuthorizationResponse("authorization response missing iss"))
    (_, None) => Ok(())
    (None, Some(_)) =>
      Err(
        InvalidAuthorizationResponse(
          "authorization server issuer is unavailable",
        ),
      )
  }
}

///|
pub fn dynamic_client_registration_request(
  client_name~ : String,
  redirect_uri~ : String,
) -> Json {
  let obj = Map([])
  obj["client_name"] = Json::string(client_name)
  obj["application_type"] = Json::string("native")
  obj["redirect_uris"] = Json::array([Json::string(redirect_uri)])
  obj["grant_types"] = Json::array([
    Json::string("authorization_code"),
    Json::string("refresh_token"),
  ])
  obj["response_types"] = Json::array([Json::string("code")])
  obj["token_endpoint_auth_method"] = Json::string("none")
  Json::object(obj)
}

///|
pub fn oauth_no_browser_json(
  authorization_url~ : String,
  callback_url~ : String,
  state~ : String,
) -> Json {
  let obj = Map([])
  obj["authorizationUrl"] = Json::string(authorization_url)
  obj["callbackUrl"] = Json::string(callback_url)
  obj["state"] = Json::string(state)
  Json::object(obj)
}

///|
fn query_pair(key : String, value : String) -> String {
  url_encode_component(key) + "=" + url_encode_component(value)
}

///|
fn url_encode_component(value : String) -> String {
  let out = StringBuilder::new(size_hint=value.length())
  let bytes = @utf8.encode(value.to_string_view(), bom=false)
  for byte in bytes {
    let value = byte.to_int()
    if is_unreserved_url_byte(value) {
      out.write_char(value.unsafe_to_char())
    } else {
      out.write_char('%')
      out.write_char(hex_digit(value / 16 % 16))
      out.write_char(hex_digit(value % 16))
    }
  }
  out.to_string()
}

///|
fn is_unreserved_url_byte(value : Int) -> Bool {
  (value >= 0x61 && value <= 0x7a) ||
  (value >= 0x41 && value <= 0x5a) ||
  (value >= 0x30 && value <= 0x39) ||
  value == 0x2d ||
  value == 0x5f ||
  value == 0x2e ||
  value == 0x7e
}

///|
fn hex_digit(value : Int) -> Char {
  "0123456789ABCDEF".to_string_view().get_char(value).unwrap()
}

///|
pub struct OAuthClientRegistration {
  client_id : String
  client_secret : String?
} derive(Debug)

///|
suberror OAuthPlanError {
  InvalidOAuthMetadata(String)
  InvalidClientRegistration(String)
  InvalidAuthorizationResponse(String)
} derive(Debug)

///|
pub fn decode_oauth_metadata(
  json : Json,
) -> Result[OAuthMetadata, OAuthPlanError] {
  let obj = expect_oauth_object(json) catch {
    _ => return Err(InvalidOAuthMetadata("metadata must be object"))
  }
  let authorization_endpoint = expect_oauth_string(
    obj.get("authorization_endpoint"),
    "authorization_endpoint",
  ) catch {
    _ =>
      return Err(InvalidOAuthMetadata("authorization_endpoint must be string"))
  }
  let token_endpoint = expect_oauth_string(
    obj.get("token_endpoint"),
    "token_endpoint",
  ) catch {
    _ => return Err(InvalidOAuthMetadata("token_endpoint must be string"))
  }
  let registration_endpoint = optional_oauth_string(
    obj.get("registration_endpoint"),
    "registration_endpoint",
  ) catch {
    _ =>
      return Err(InvalidOAuthMetadata("registration_endpoint must be string"))
  }
  let scopes_supported = optional_oauth_string_array(
    obj.get("scopes_supported"),
    "scopes_supported",
  ) catch {
    _ =>
      return Err(InvalidOAuthMetadata("scopes_supported must be string array"))
  }
  let issuer = optional_oauth_string(obj.get("issuer"), "issuer") catch {
    _ => return Err(InvalidOAuthMetadata("issuer must be string"))
  }
  let iss_supported = match
    obj.get("authorization_response_iss_parameter_supported") {
    None | Some(Null) => false
    Some(True) => true
    Some(False) => false
    _ =>
      return Err(
        InvalidOAuthMetadata(
          "authorization_response_iss_parameter_supported must be boolean",
        ),
      )
  }
  if iss_supported && issuer is None {
    return Err(
      InvalidOAuthMetadata(
        "issuer is required when authorization response iss is supported",
      ),
    )
  }
  Ok({
    authorization_endpoint,
    token_endpoint,
    registration_endpoint,
    scopes_supported,
    issuer,
    authorization_response_iss_parameter_supported: iss_supported,
  })
}

///|
pub fn decode_client_registration_response(
  json : Json,
) -> Result[OAuthClientRegistration, OAuthPlanError] {
  let obj = expect_oauth_object(json) catch {
    _ => return Err(InvalidClientRegistration("response must be object"))
  }
  let client_id = expect_oauth_string(obj.get("client_id"), "client_id") catch {
    _ => return Err(InvalidClientRegistration("client_id must be string"))
  }
  let client_secret = optional_oauth_string(
    obj.get("client_secret"),
    "client_secret",
  ) catch {
    _ => return Err(InvalidClientRegistration("client_secret must be string"))
  }
  Ok({ client_id, client_secret })
}

///|
fn expect_oauth_object(json : Json) -> Map[String, Json] raise OAuthPlanError {
  match json {
    Object(obj) => obj
    _ => raise InvalidOAuthMetadata("must be object")
  }
}

///|
fn expect_oauth_string(
  json : Json?,
  field : String,
) -> String raise OAuthPlanError {
  match json {
    Some(String(value)) => value
    _ => raise InvalidOAuthMetadata(field + " must be string")
  }
}

///|
fn optional_oauth_string(
  json : Json?,
  field : String,
) -> String? raise OAuthPlanError {
  match json {
    None | Some(Null) => None
    Some(String(value)) => Some(value)
    _ => raise InvalidOAuthMetadata(field + " must be string")
  }
}

///|
fn optional_oauth_string_array(
  json : Json?,
  field : String,
) -> Array[String] raise OAuthPlanError {
  match json {
    None | Some(Null) => []
    Some(Array(values)) => {
      let result = []
      for value in values {
        match value {
          String(text) => result.push(text)
          _ => raise InvalidOAuthMetadata(field + " must contain strings")
        }
      }
      result
    }
    _ => raise InvalidOAuthMetadata(field + " must be array")
  }
}

///|
pub fn authorization_code_token_request_body(
  client_id~ : String,
  client_secret~ : String?,
  code~ : String,
  redirect_uri~ : String,
  code_verifier~ : String,
) -> String {
  let pairs = [
    query_pair("grant_type", "authorization_code"),
    query_pair("client_id", client_id),
  ]
  match client_secret {
    Some(secret) => pairs.push(query_pair("client_secret", secret))
    None => ()
  }
  pairs.push(query_pair("code", code))
  pairs.push(query_pair("redirect_uri", redirect_uri))
  pairs.push(query_pair("code_verifier", code_verifier))
  pairs.join("&")
}

///|
pub fn refresh_token_request_body(
  client_id~ : String,
  client_secret~ : String?,
  refresh_token~ : String,
) -> String {
  let pairs = [
    query_pair("grant_type", "refresh_token"),
    query_pair("client_id", client_id),
  ]
  match client_secret {
    Some(secret) => pairs.push(query_pair("client_secret", secret))
    None => ()
  }
  pairs.push(query_pair("refresh_token", refresh_token))
  pairs.join("&")
}

///|
pub fn decode_oauth_token_response(
  json : Json,
  issued_at~ : Int,
) -> Result[OAuthTokens, OAuthPlanError] {
  let obj = expect_oauth_object(json) catch {
    _ => return Err(InvalidOAuthMetadata("token response must be object"))
  }
  let access_token = expect_oauth_string(
    obj.get("access_token"),
    "access_token",
  ) catch {
    _ => return Err(InvalidOAuthMetadata("access_token must be string"))
  }
  let refresh_token = optional_oauth_string(
    obj.get("refresh_token"),
    "refresh_token",
  ) catch {
    _ => return Err(InvalidOAuthMetadata("refresh_token must be string"))
  }
  let expires_in = optional_oauth_int(obj.get("expires_in"), "expires_in") catch {
    _ => return Err(InvalidOAuthMetadata("expires_in must be int"))
  }
  let expires_at = match expires_in {
    None => None
    Some(expires_in) =>
      Some(expires_at_from_expires_in(issued_at~, expires_in~))
  }
  Ok(oauth_tokens(access_token, refresh_token~, expires_at~))
}

///|
fn optional_oauth_int(
  json : Json?,
  field : String,
) -> Int? raise OAuthPlanError {
  match json {
    None | Some(Null) => None
    Some(Number(value, ..)) if value.trunc() == value => Some(value.to_int())
    _ => raise InvalidOAuthMetadata(field + " must be int")
  }
}
