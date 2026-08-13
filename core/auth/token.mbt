///|
pub struct OAuthTokens {
  access_token : String
  refresh_token : String?
  expires_at : Int?
} derive(Debug)

///|
pub enum TokenRefreshDecision {
  UseCached
  Refresh
  ReauthRequired
} derive(Debug)

///|
pub fn oauth_tokens(
  access_token : String,
  refresh_token? : String? = None,
  expires_at? : Int? = None,
) -> OAuthTokens {
  { access_token, refresh_token, expires_at }
}

///|
pub fn expires_at_from_expires_in(issued_at~ : Int, expires_in~ : Int) -> Int {
  issued_at + expires_in
}

///|
pub fn decide_token_refresh(
  tokens : OAuthTokens,
  now_seconds~ : Int,
  skew_seconds? : Int = 300,
) -> TokenRefreshDecision {
  match tokens.expires_at {
    None => UseCached
    Some(expires_at) =>
      if expires_at > now_seconds + skew_seconds {
        UseCached
      } else {
        match tokens.refresh_token {
          Some(_) => Refresh
          None => ReauthRequired
        }
      }
  }
}
