///|
#cfg(all(target="native", not(platform="windows")))
async test "oauth callback: captures code with matching state" {
  let result = wait_for_oauth_callback(
    port=0,
    path="/callback",
    expected_state="state-1",
    timeout_ms=1000,
    trigger=redirect_uri => {
      ignore(@http.get(redirect_uri + "?code=code-1&state=state-1"))
    },
  )
  inspect(result.code + ":" + result.state, content="code-1:state-1")
  inspect(result.issuer is None, content="true")
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "oauth callback: captures and decodes RFC 9207 issuer" {
  let result = wait_for_oauth_callback(
    port=0,
    path="/callback",
    expected_state="state-1",
    timeout_ms=1000,
    trigger=redirect_uri => {
      ignore(
        @http.get(
          redirect_uri +
          "?code=code-1&state=state-1&iss=https%3A%2F%2Fauth.example",
        ),
      )
    },
  )
  inspect(result.issuer.unwrap(), content="https://auth.example")
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "oauth callback: rejects mismatched state" {
  let result : Result[OAuthCallbackCode, OAuthCallbackError] = try
    wait_for_oauth_callback(
      port=0,
      path="/callback",
      expected_state="state-1",
      timeout_ms=1000,
      trigger=redirect_uri => {
        ignore(@http.get(redirect_uri + "?code=code-1&state=wrong"))
      },
    )
    |> Ok
  catch {
    e => Err(e)
  }
  @debug.debug_inspect(result, content="Err(StateMismatch)")
}
