///|
test "token: expires_at is derived from expires_in" {
  inspect(
    @auth.expires_at_from_expires_in(issued_at=1000, expires_in=3600),
    content="4600",
  )
}

///|
test "token: valid cached token can be used" {
  let token = @auth.oauth_tokens(
    "access",
    refresh_token=Some("refresh"),
    expires_at=Some(2000),
  )
  @debug.debug_inspect(
    @auth.decide_token_refresh(token, now_seconds=1000, skew_seconds=300),
    content="UseCached",
  )
}

///|
test "token: near-expiry token with refresh token should refresh" {
  let token = @auth.oauth_tokens(
    "access",
    refresh_token=Some("refresh"),
    expires_at=Some(1200),
  )
  @debug.debug_inspect(
    @auth.decide_token_refresh(token, now_seconds=1000, skew_seconds=300),
    content="Refresh",
  )
}

///|
test "token: near-expiry token without refresh token requires reauth" {
  let token = @auth.oauth_tokens("access", expires_at=Some(1200))
  @debug.debug_inspect(
    @auth.decide_token_refresh(token, now_seconds=1000, skew_seconds=300),
    content="ReauthRequired",
  )
}

///|
test "token: token without expiry is usable" {
  let token = @auth.oauth_tokens("access")
  @debug.debug_inspect(
    @auth.decide_token_refresh(token, now_seconds=1000, skew_seconds=300),
    content="UseCached",
  )
}
