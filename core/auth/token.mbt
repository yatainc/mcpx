///|
#derive(Debug)
pub struct OAuthTokens {
  access_token : String
  refresh_token : String?
  expires_at : Int32?
}

///|
pub extend OAuthTokens with Debug::{to_repr}

///|
#derive(Debug)
pub enum TokenRefreshDecision {
  UseCached
  Refresh
  ReauthRequired
}

///|
pub extend TokenRefreshDecision with Debug::{to_repr}

///|
pub fn oauth_tokens(
  access_token : String,
  refresh_token~ : String? = None,
  expires_at~ : Int32? = None,
) -> OAuthTokens {
  { access_token, refresh_token, expires_at, }
}

///|
pub fn expires_at_from_expires_in(
  issued_at~ : Int32,
  expires_in~ : Int32,
) -> Int32 {
  issued_at + expires_in
}

///|
pub fn decide_token_refresh(
  tokens : OAuthTokens,
  now_seconds~ : Int32,
  skew_seconds~ : Int32 = 300,
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
