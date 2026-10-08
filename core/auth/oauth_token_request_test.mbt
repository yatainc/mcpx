///|
test "oauth token request: authorization code with public PKCE client" {
  inspect(
    @auth.authorization_code_token_request_body(
      client_id="client-1",
      client_secret=None,
      code="code 1",
      redirect_uri="http://127.0.0.1:8765/callback",
      code_verifier="verifier-1",
    ),
    content="grant_type=authorization_code&client_id=client-1&code=code%201&redirect_uri=http%3A%2F%2F127.0.0.1%3A8765%2Fcallback&code_verifier=verifier-1",
  )
}

///|
test "oauth token request: authorization code with static secret" {
  inspect(
    @auth.authorization_code_token_request_body(
      client_id="client-1",
      client_secret=Some("secret 1"),
      code="code-1",
      redirect_uri="http://127.0.0.1:8765/callback",
      code_verifier="verifier-1",
    ),
    content="grant_type=authorization_code&client_id=client-1&client_secret=secret%201&code=code-1&redirect_uri=http%3A%2F%2F127.0.0.1%3A8765%2Fcallback&code_verifier=verifier-1",
  )
}

///|
test "oauth token request: refresh with optional client secret" {
  inspect(
    @auth.refresh_token_request_body(
      client_id="client-1",
      client_secret=Some("secret 1"),
      refresh_token="refresh 1",
    ),
    content="grant_type=refresh_token&client_id=client-1&client_secret=secret%201&refresh_token=refresh%201",
  )
}
