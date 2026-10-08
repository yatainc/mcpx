///|
test "oauth token response: decodes expires_in into expires_at" {
  let json = Json::object({
    "access_token": Json::string("access-1"),
    "refresh_token": Json::string("refresh-1"),
    "expires_in": Json::number(3600.0, repr="3600"),
    "token_type": Json::string("Bearer"),
  })
  @debug.debug_inspect(
    @auth.decode_oauth_token_response(json, issued_at=1000),
    content=(
      #|Ok(
      #|  {
      #|    access_token: "access-1",
      #|    refresh_token: Some("refresh-1"),
      #|    expires_at: Some(4600),
      #|  },
      #|)
    ),
  )
}

///|
test "oauth token response: missing refresh token is allowed" {
  let json = Json::object({
    "access_token": Json::string("access-1"),
    "expires_in": Json::number(3600.0, repr="3600"),
  })
  @debug.debug_inspect(
    @auth.decode_oauth_token_response(json, issued_at=1000),
    content=(
      #|Ok(
      #|  {
      #|    access_token: "access-1",
      #|    refresh_token: None,
      #|    expires_at: Some(4600),
      #|  },
      #|)
    ),
  )
}
