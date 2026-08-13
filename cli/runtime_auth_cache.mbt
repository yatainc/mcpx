///|
async fn call_headers_with_cached_auth(
  server_name~ : String,
  server_url~ : String,
  server~ : @config.McpServerConfig,
  credentials_path~ : String,
) -> Result[Map[String, String], String] {
  let headers = server.headers.copy()
  if has_authorization_header(headers) {
    Ok(headers)
  } else {
    match server.auth {
      None => Ok(headers)
      Some(auth) => {
        let credentials = @storage.load_credentials_file_or_empty(
          credentials_path,
        ) catch {
          _ => return Err("failed to load credentials")
        }
        let entry = @auth.find_credentials_entry(
          credentials,
          server_name~,
          server_url=Some(server_url),
        )
        match
          @auth.decide_auth_cache(entry, now_seconds=current_time_seconds()) {
          UseBearerHeader(value) => {
            prune_cached_oauth_credentials(
              server_name~,
              server_url~,
              auth~,
              credentials_path~,
            )
            headers["Authorization"] = value
            Ok(headers)
          }
          RefreshWithToken(refresh_token) =>
            match entry {
              Some(entry) =>
                match
                  refresh_oauth_credentials(
                    server_name~,
                    server_url~,
                    auth~,
                    entry~,
                    refresh_token~,
                    credentials_path~,
                  ) {
                  Ok(value) => {
                    headers["Authorization"] = value
                    Ok(headers)
                  }
                  Err(message) => Err(message)
                }
              None =>
                Err("authentication required: run mcpx auth " + server_name)
            }
          ReauthRequired =>
            Err("authentication required: run mcpx auth " + server_name)
        }
      }
    }
  }
}

///|
fn prune_cached_oauth_credentials(
  server_name~ : String,
  server_url~ : String,
  auth~ : @config.ServerAuthConfig,
  credentials_path~ : String,
) -> Unit {
  let snapshot = match load_credentials_snapshot_or_empty(credentials_path) {
    Ok(value) => value
    Err(_) => return
  }
  let pruned = match
    @auth.find_credentials_entry(
      snapshot.file,
      server_name~,
      server_url=Some(server_url),
    ) {
    Some(entry) =>
      match oauth_client_id(auth, entry) {
        Some(client_id) =>
          @auth.replace_server_credentials_entry(
            snapshot.file,
            credentials_cache_key(server_name, client_id),
            entry,
          )
        None => snapshot.file
      }
    None => snapshot.file
  }
  if snapshot.text != @auth.credentials_file_json(pruned) {
    ignore(
      save_credentials_file_if_unchanged(
        credentials_path,
        snapshot.text,
        pruned,
        error_message="failed to save credentials",
      ),
    )
  }
}

///|
async fn refresh_oauth_credentials(
  server_name~ : String,
  server_url~ : String,
  auth~ : @config.ServerAuthConfig,
  entry~ : @auth.CredentialsEntry,
  refresh_token~ : String,
  credentials_path~ : String,
) -> Result[String, String] {
  let client_id = match oauth_client_id(auth, entry) {
    Some(value) => value
    None => return Err("authentication required: run mcpx auth " + server_name)
  }
  let metadata = match
    resolve_oauth_metadata(
      server_name~,
      server_url=Some(server_url),
      metadata_url=auth.metadata_url,
    ) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let issued_at = current_time_seconds()
  let body = @auth.refresh_token_request_body(
    client_id~,
    client_secret=auth.client_secret,
    refresh_token~,
  )
  let (response, data) = @http.post(metadata.token_endpoint, body, headers={
    "content-type": "application/x-www-form-urlencoded",
    "accept": "application/json",
  }) catch {
    _ => return Err("failed to refresh OAuth token")
  }
  if response.code != 200 {
    return Err("failed to refresh OAuth token")
  }
  let token_json = data.json() catch {
    _ => return Err("invalid OAuth token response")
  }
  let tokens = match @auth.decode_oauth_token_response(token_json, issued_at~) {
    Ok(value) => value
    Err(_) => return Err("invalid OAuth token response")
  }
  let refresh_token_next = match tokens.refresh_token {
    Some(value) => Some(value)
    None => Some(refresh_token)
  }
  let updated_entry = @auth.credentials_entry(
    server_name~,
    server_url=Some(server_url),
    client_id=Some(client_id),
    access_token=tokens.access_token,
    refresh_token=refresh_token_next,
    expires_at=tokens.expires_at,
    updated_at=issued_at.to_string(),
  )
  let latest_snapshot = match
    load_credentials_snapshot_or_empty(credentials_path) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let current_entry = @auth.find_credentials_entry(
    latest_snapshot.file,
    server_name~,
    server_url=Some(server_url),
  )
  if !same_refresh_credentials_source(auth, current_entry, entry, refresh_token) {
    return cached_auth_after_refresh_race(current_entry)
  }
  let updated_credentials = @auth.replace_server_credentials_entry(
    latest_snapshot.file,
    credentials_cache_key(server_name, client_id),
    updated_entry,
  )
  match
    save_credentials_file_if_unchanged(
      credentials_path,
      latest_snapshot.text,
      updated_credentials,
      error_message="failed to save refreshed credentials",
    ) {
    Ok(true) => Ok("Bearer " + tokens.access_token)
    Ok(false) => {
      let newest_snapshot = match
        load_credentials_snapshot_or_empty(credentials_path) {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      let newest_entry = @auth.find_credentials_entry(
        newest_snapshot.file,
        server_name~,
        server_url=Some(server_url),
      )
      cached_auth_after_refresh_race(newest_entry)
    }
    Err(message) => Err(message)
  }
}

///|
async fn fetch_oauth_metadata(
  metadata_url : String,
  expected_issuer? : String? = None,
) -> Result[@auth.OAuthMetadata, String] {
  let (response, data) = @http.get(metadata_url, headers={
    "accept": "application/json",
  }) catch {
    _ => return Err("failed to fetch OAuth metadata")
  }
  if response.code != 200 {
    return Err("failed to fetch OAuth metadata")
  }
  let metadata_json = data.json() catch {
    _ => return Err("invalid OAuth metadata")
  }
  let metadata = match @auth.decode_oauth_metadata(metadata_json) {
    Ok(value) => value
    Err(_) => return Err("invalid OAuth metadata")
  }
  match expected_issuer {
    Some(expected) =>
      match metadata.issuer {
        Some(actual) if actual == expected => Ok(metadata)
        _ => Err("OAuth metadata issuer mismatch")
      }
    None => Ok(metadata)
  }
}

///|
fn cached_auth_after_refresh_race(
  current : @auth.CredentialsEntry?,
) -> Result[String, String] {
  match @auth.decide_auth_cache(current, now_seconds=current_time_seconds()) {
    UseBearerHeader(value) => Ok(value)
    _ => Err("credentials changed during OAuth refresh; retry")
  }
}

///|
fn same_refresh_credentials_source(
  auth : @config.ServerAuthConfig,
  current : @auth.CredentialsEntry?,
  original : @auth.CredentialsEntry,
  refresh_token : String,
) -> Bool {
  match current {
    Some(value) =>
      oauth_client_id(auth, value) == oauth_client_id(auth, original) &&
      value.tokens.access_token == original.tokens.access_token &&
      value.tokens.refresh_token == Some(refresh_token) &&
      value.tokens.expires_at == original.tokens.expires_at &&
      value.updated_at == original.updated_at
    None => false
  }
}

///|
fn oauth_client_id(
  auth : @config.ServerAuthConfig,
  entry : @auth.CredentialsEntry,
) -> String? {
  match auth.client_id {
    Some(value) => Some(value)
    None =>
      match entry.client_info {
        Some(info) => Some(info.client_id)
        None => None
      }
  }
}

///|
fn credentials_cache_key(server_name : String, client_id : String) -> String {
  server_name + "|" + client_id
}

///|
fn has_authorization_header(headers : Map[String, String]) -> Bool {
  headers.contains("Authorization") || headers.contains("authorization")
}
