///|
test "auth host actions oauth: metadata discovery is host HTTP GET" {
  inspect(
    oauth_metadata_request_action(
      "https://mcp.example/.well-known/oauth-authorization-server",
    )
    .to_json()
    .stringify(),
    content=(
      #|{"kind":"http_request","method":"GET","url":"https://mcp.example/.well-known/oauth-authorization-server","headers":{"accept":"application/json"}}
    ),
  )
}

///|
test "auth host actions oauth: dynamic client registration is host HTTP POST" {
  let metadata = oauth_metadata(
    authorization_endpoint="https://auth.example/authorize",
    token_endpoint="https://auth.example/token",
    registration_endpoint=Some("https://auth.example/register"),
  )
  inspect(
    oauth_dynamic_client_registration_action(
      metadata,
      client_name="mcpx",
      redirect_uri="http://127.0.0.1:8765/callback",
    )
    .to_json()
    .stringify(),
    content=(
      #|{"kind":"http_request","method":"POST","url":"https://auth.example/register","headers":{"content-type":"application/json","accept":"application/json"},"body":"{\"client_name\":\"mcpx\",\"application_type\":\"native\",\"redirect_uris\":[\"http://127.0.0.1:8765/callback\"],\"grant_types\":[\"authorization_code\",\"refresh_token\"],\"response_types\":[\"code\"],\"token_endpoint_auth_method\":\"none\"}"}
    ),
  )
}

///|
test "auth host actions oauth: token exchange is form POST" {
  let metadata = oauth_metadata(
    authorization_endpoint="https://auth.example/authorize",
    token_endpoint="https://auth.example/token",
  )
  inspect(
    oauth_token_exchange_action(
      metadata,
      client_id="client-1",
      client_secret=None,
      code="code-1",
      redirect_uri="http://127.0.0.1:8765/callback",
      code_verifier="verifier-1",
    )
    .to_json()
    .stringify(),
    content=(
      #|{"kind":"http_request","method":"POST","url":"https://auth.example/token","headers":{"content-type":"application/x-www-form-urlencoded","accept":"application/json"},"body":"grant_type=authorization_code&client_id=client-1&code=code-1&redirect_uri=http%3A%2F%2F127.0.0.1%3A8765%2Fcallback&code_verifier=verifier-1"}
    ),
  )
}
