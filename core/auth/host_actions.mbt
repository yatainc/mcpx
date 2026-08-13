///|
pub enum CachedAuthDecision {
  UseBearerHeader(String)
  RefreshWithToken(String)
  ReauthRequired
} derive(Debug)

///|
pub fn credentials_lookup_action(
  credentials_path~ : String,
) -> @host.HostAction {
  @host.host_read_text_file(path=credentials_path)
}

///|
pub fn credentials_write_action(
  credentials_path~ : String,
  file : CredentialsFile,
) -> @host.HostAction {
  @host.host_write_private_text_file(
    path=credentials_path,
    contents=credentials_file_json(file),
  )
}

///|
pub fn decide_auth_cache(
  entry : CredentialsEntry?,
  now_seconds~ : Int,
  skew_seconds? : Int = 300,
) -> CachedAuthDecision {
  match entry {
    None => ReauthRequired
    Some(entry) =>
      match decide_token_refresh(entry.tokens, now_seconds~, skew_seconds~) {
        UseCached => UseBearerHeader("Bearer " + entry.tokens.access_token)
        Refresh =>
          match entry.tokens.refresh_token {
            Some(refresh_token) => RefreshWithToken(refresh_token)
            None => ReauthRequired
          }
        ReauthRequired => ReauthRequired
      }
  }
}

///|
pub fn oauth_metadata_request_action(metadata_url : String) -> @host.HostAction {
  @host.host_http_request(http_method="GET", url=metadata_url, headers={
    "accept": "application/json",
  })
}

///|
pub fn oauth_dynamic_client_registration_action(
  metadata : OAuthMetadata,
  client_name~ : String,
  redirect_uri~ : String,
) -> @host.HostAction {
  @host.host_http_request(
    http_method="POST",
    url=metadata.registration_endpoint.unwrap_or(""),
    headers={ "content-type": "application/json", "accept": "application/json" },
    body=Some(
      dynamic_client_registration_request(client_name~, redirect_uri~).stringify(),
    ),
  )
}

///|
pub fn oauth_token_exchange_action(
  metadata : OAuthMetadata,
  client_id~ : String,
  client_secret~ : String?,
  code~ : String,
  redirect_uri~ : String,
  code_verifier~ : String,
) -> @host.HostAction {
  @host.host_http_request(
    http_method="POST",
    url=metadata.token_endpoint,
    headers={
      "content-type": "application/x-www-form-urlencoded",
      "accept": "application/json",
    },
    body=Some(
      authorization_code_token_request_body(
        client_id~,
        client_secret~,
        code~,
        redirect_uri~,
        code_verifier~,
      ),
    ),
  )
}

///|
pub fn oauth_refresh_token_action(
  metadata : OAuthMetadata,
  client_id~ : String,
  client_secret~ : String?,
  refresh_token~ : String,
) -> @host.HostAction {
  @host.host_http_request(
    http_method="POST",
    url=metadata.token_endpoint,
    headers={
      "content-type": "application/x-www-form-urlencoded",
      "accept": "application/json",
    },
    body=Some(
      refresh_token_request_body(client_id~, client_secret~, refresh_token~),
    ),
  )
}
