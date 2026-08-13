///|
test "oauth plan: empty requested scopes returns empty" {
  let metadata = oauth_metadata(
    authorization_endpoint="https://auth.example/authorize",
    token_endpoint="https://auth.example/token",
    scopes_supported=["repo", "read:user"],
  )
  inspect(
    select_oauth_scopes(metadata, requested_scopes=[]).is_empty(),
    content="true",
  )
}

///|
test "oauth plan: explicit requested scopes override metadata defaults" {
  let metadata = oauth_metadata(
    authorization_endpoint="https://auth.example/authorize",
    token_endpoint="https://auth.example/token",
    scopes_supported=["repo", "read:user"],
  )
  inspect(
    select_oauth_scopes(metadata, requested_scopes=["admin:org"]).join(" "),
    content="admin:org",
  )
}

///|
test "oauth plan: builds PKCE authorization URL" {
  let metadata = oauth_metadata(
    authorization_endpoint="https://auth.example/authorize",
    token_endpoint="https://auth.example/token",
    scopes_supported=["repo", "read:user"],
  )
  inspect(
    oauth_authorization_url(
      metadata,
      client_id="client 1",
      redirect_uri="http://127.0.0.1:8765/callback",
      state="state-1",
      code_challenge="challenge-1",
      scopes=["repo", "read:user"],
    ),
    content="https://auth.example/authorize?response_type=code&client_id=client%201&redirect_uri=http%3A%2F%2F127.0.0.1%3A8765%2Fcallback&code_challenge=challenge-1&code_challenge_method=S256&state=state-1&scope=repo%20read%3Auser",
  )
}

///|
test "oauth plan: percent-encodes UTF-8 authorization parameters" {
  let metadata = oauth_metadata(
    authorization_endpoint="https://auth.example/authorize",
    token_endpoint="https://auth.example/token",
  )
  let url = oauth_authorization_url(
    metadata,
    client_id="検索",
    redirect_uri="http://localhost/callback",
    state="状態",
    code_challenge="challenge",
    scopes=["読み取り"],
  )
  inspect(url.contains("client_id=%E6%A4%9C%E7%B4%A2"), content="true")
  inspect(url.contains("state=%E7%8A%B6%E6%85%8B"), content="true")
  inspect(
    url.contains("scope=%E8%AA%AD%E3%81%BF%E5%8F%96%E3%82%8A"),
    content="true",
  )
}

///|
test "oauth plan: omits scope parameter when scopes are empty" {
  let metadata = oauth_metadata(
    authorization_endpoint="https://auth.example/authorize",
    token_endpoint="https://auth.example/token",
  )
  let url = oauth_authorization_url(
    metadata,
    client_id="client-1",
    redirect_uri="http://127.0.0.1:8765/callback",
    state="state-1",
    code_challenge="challenge-1",
    scopes=[],
  )
  inspect(!url.contains("scope="), content="true")
}

///|
test "oauth plan: dynamic client registration request is JSON" {
  inspect(
    dynamic_client_registration_request(
      client_name="mcpx",
      redirect_uri="http://127.0.0.1:8765/callback",
    ).stringify(),
    content=(
      #|{"client_name":"mcpx","application_type":"native","redirect_uris":["http://127.0.0.1:8765/callback"],"grant_types":["authorization_code","refresh_token"],"response_types":["code"],"token_endpoint_auth_method":"none"}
    ),
  )
}

///|
test "oauth plan: no-browser json exposes URL but not verifier" {
  let output = oauth_no_browser_json(
    authorization_url="https://auth.example/authorize?client_id=client",
    callback_url="http://127.0.0.1:8765/callback",
    state="state-1",
  )
  inspect(
    output.stringify(),
    content=(
      #|{"authorizationUrl":"https://auth.example/authorize?client_id=client","callbackUrl":"http://127.0.0.1:8765/callback","state":"state-1"}
    ),
  )
}

///|
test "oauth plan: decodes authorization server metadata" {
  let json = Json::object({
    "authorization_endpoint": Json::string("https://auth.example/authorize"),
    "token_endpoint": Json::string("https://auth.example/token"),
    "registration_endpoint": Json::string("https://auth.example/register"),
    "scopes_supported": Json::array([
      Json::string("repo"),
      Json::string("read:user"),
    ]),
  })
  @debug.debug_inspect(
    decode_oauth_metadata(json),
    content=(
      #|Ok(
      #|  {
      #|    authorization_endpoint: "https://auth.example/authorize",
      #|    token_endpoint: "https://auth.example/token",
      #|    registration_endpoint: Some("https://auth.example/register"),
      #|    scopes_supported: ["repo", "read:user"],
      #|    issuer: None,
      #|    authorization_response_iss_parameter_supported: false,
      #|  },
      #|)
    ),
  )
}

///|
test "oauth plan: validates RFC 9207 authorization response issuer" {
  let metadata = oauth_metadata(
    authorization_endpoint="https://auth.example/authorize",
    token_endpoint="https://auth.example/token",
    issuer=Some("https://auth.example"),
    authorization_response_iss_parameter_supported=true,
  )
  inspect(
    validate_authorization_response_issuer(
      metadata,
      Some("https://auth.example"),
    )
    is Ok(_),
    content="true",
  )
  inspect(
    validate_authorization_response_issuer(metadata, None) is Err(_),
    content="true",
  )
  inspect(
    validate_authorization_response_issuer(
      metadata,
      Some("https://attacker.example"),
    )
    is Err(_),
    content="true",
  )
}

///|
test "oauth plan: rejects unexpected issuer even without advertised support" {
  let metadata = oauth_metadata(
    authorization_endpoint="https://auth.example/authorize",
    token_endpoint="https://auth.example/token",
    issuer=Some("https://auth.example"),
  )
  inspect(
    validate_authorization_response_issuer(
      metadata,
      Some("https://attacker.example"),
    )
    is Err(_),
    content="true",
  )
}

///|
test "oauth plan: decodes RFC 9207 metadata" {
  let decoded = decode_oauth_metadata({
    "issuer": "https://auth.example",
    "authorization_endpoint": "https://auth.example/authorize",
    "token_endpoint": "https://auth.example/token",
    "authorization_response_iss_parameter_supported": true,
  }).unwrap()
  inspect(decoded.issuer.unwrap(), content="https://auth.example")
  inspect(
    decoded.authorization_response_iss_parameter_supported,
    content="true",
  )
}

///|
test "oauth plan: decodes dynamic client registration response" {
  let json = Json::object({
    "client_id": Json::string("client-1"),
    "client_secret": Json::string("secret-1"),
  })
  @debug.debug_inspect(
    decode_client_registration_response(json),
    content=(
      #|Ok({ client_id: "client-1", client_secret: Some("secret-1") })
    ),
  )
}
