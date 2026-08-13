///|
priv struct CredentialsSnapshot {
  file : @auth.CredentialsFile
  text : String
}

///|
async fn run_auth(
  command : AuthCommand,
  home : String,
  config_home : String?,
) -> String {
  if command.issuer is Some(_) && command.code is None {
    return error_result("OAuth code is required")
  }
  match (command.code, command.state) {
    (Some(code), Some(state)) =>
      return complete_oauth_auth(
        command.server,
        code,
        state,
        command.issuer,
        home,
        config_home,
      )
    (Some(_), None) => return error_result("OAuth state is required")
    (None, Some(_)) => return error_result("OAuth code is required")
    (None, None) => ()
  }
  let paths = @app_paths.mcpx_app_paths(home, config_home~)
  let config = @storage.load_mcpx_config_or_empty(paths.servers_config)
  match config.servers.get(command.server) {
    None => error_result("server not found: " + command.server)
    Some(server) => {
      let env = match load_mcpx_env(paths.env_file) {
        Ok(value) => value
        Err(message) => return error_result(message)
      }
      let resolved_server = match @config.resolve_server_env(server, env) {
        Ok(value) => value
        Err(error) => return error_result(error.to_string())
      }
      let auth = match resolved_server.auth {
        Some(value) => value
        None =>
          return error_result("server has no OAuth config: " + command.server)
      }
      let metadata = match
        resolve_oauth_metadata(
          server_name=command.server,
          server_url=resolved_server.url,
          metadata_url=auth.metadata_url,
        ) {
        Ok(value) => value
        Err(message) => return error_result(message)
      }
      let redirect_uri = "http://127.0.0.1:8765/callback"
      let (client_id, client_secret) = match auth.client_id {
        Some(value) => (value, auth.client_secret)
        None =>
          match register_oauth_client(metadata, redirect_uri) {
            Ok(value) => (value.client_id, value.client_secret)
            Err(message) => return error_result(message)
          }
      }
      let state = @oauth.random_urlsafe_token(16) catch {
        _ => return error_result("failed to generate OAuth state")
      }
      let verifier = @oauth.random_urlsafe_token(32) catch {
        _ => return error_result("failed to generate OAuth verifier")
      }
      let challenge = @oauth.pkce_s256_challenge(verifier)
      let scopes = @auth.select_oauth_scopes(
        metadata,
        requested_scopes=auth.scopes,
      )
      let authorization_url = @auth.oauth_authorization_url(
        metadata,
        client_id~,
        redirect_uri~,
        state~,
        code_challenge=challenge,
        scopes~,
      )
      let save_result = save_pending_oauth_flow(
        paths.credentials_file,
        server_name=command.server,
        server_url=resolved_server.url,
        client_id~,
        client_secret~,
        token_endpoint=metadata.token_endpoint,
        authorization_issuer=metadata.issuer,
        require_authorization_issuer=metadata.authorization_response_iss_parameter_supported,
        redirect_uri~,
        code_verifier=verifier,
        state~,
      )
      match save_result {
        Ok(_) => ()
        Err(message) => return error_result(message)
      }
      if command.no_browser {
        auth_start_result(
          command.server,
          authorization_url,
          redirect_uri,
          state,
        )
      } else {
        let callback = @oauth.wait_for_oauth_callback(
          port=8765,
          path="/callback",
          expected_state=state,
          timeout_ms=300000,
          trigger=_redirect_uri => {
            @oauth.open_authorization_url(authorization_url)
          },
        ) catch {
          _ => return error_result("OAuth callback failed or timed out")
        }
        complete_oauth_auth(
          command.server,
          callback.code,
          callback.state,
          callback.issuer,
          home,
          config_home,
        )
      }
    }
  }
}

///|
async fn complete_oauth_auth(
  server_name : String,
  code : String,
  state : String,
  response_issuer : String?,
  home : String,
  config_home : String?,
) -> String {
  let paths = @app_paths.mcpx_app_paths(home, config_home~)
  let snapshot = match
    load_credentials_snapshot_or_empty(paths.credentials_file) {
    Ok(value) => value
    Err(message) => return error_result(message)
  }
  let flow = match
    @auth.find_pending_oauth_flow(snapshot.file, server_name~, state~) {
    Some(value) => value
    None => return error_result("pending OAuth flow not found: " + server_name)
  }
  let issuer_metadata = @auth.oauth_metadata(
    authorization_endpoint="",
    token_endpoint=flow.token_endpoint,
    issuer=flow.authorization_issuer,
    authorization_response_iss_parameter_supported=flow.require_authorization_issuer,
  )
  match
    @auth.validate_authorization_response_issuer(
      issuer_metadata, response_issuer,
    ) {
    Ok(_) => ()
    Err(_) =>
      return error_result("OAuth authorization response issuer mismatch")
  }
  let issued_at = current_time_seconds()
  let body = @auth.authorization_code_token_request_body(
    client_id=flow.client_info.client_id,
    client_secret=flow.client_info.client_secret,
    code~,
    redirect_uri=flow.redirect_uri,
    code_verifier=flow.code_verifier,
  )
  let (response, data) = @http.post(flow.token_endpoint, body, headers={
    "content-type": "application/x-www-form-urlencoded",
    "accept": "application/json",
  }) catch {
    _ => return error_result("failed to exchange OAuth code")
  }
  if response.code != 200 {
    return error_result("failed to exchange OAuth code")
  }
  let token_json = data.json() catch {
    _ => return error_result("invalid OAuth token response")
  }
  let tokens = match @auth.decode_oauth_token_response(token_json, issued_at~) {
    Ok(value) => value
    Err(_) => return error_result("invalid OAuth token response")
  }
  let entry = @auth.credentials_entry(
    server_name~,
    server_url=flow.server_url,
    client_id=Some(flow.client_info.client_id),
    access_token=tokens.access_token,
    refresh_token=tokens.refresh_token,
    expires_at=tokens.expires_at,
    updated_at=issued_at.to_string(),
  )
  let latest_snapshot = match
    load_credentials_snapshot_or_empty(paths.credentials_file) {
    Ok(value) => value
    Err(message) => return error_result(message)
  }
  match
    @auth.find_pending_oauth_flow(latest_snapshot.file, server_name~, state~) {
    Some(latest_flow) =>
      if !same_pending_oauth_flow(latest_flow, flow) {
        return error_result("pending OAuth flow was superseded: " + server_name)
      }
    None =>
      return error_result("pending OAuth flow was superseded: " + server_name)
  }
  let without_pending = @auth.remove_server_pending_oauth_flows(
    latest_snapshot.file,
    server_name,
  )
  let next = @auth.replace_server_credentials_entry(
    without_pending,
    credentials_cache_key(server_name, flow.client_info.client_id),
    entry,
  )
  match
    save_credentials_file_if_unchanged(
      paths.credentials_file,
      latest_snapshot.text,
      next,
      error_message="failed to save credentials",
    ) {
    Ok(true) => ()
    Ok(false) =>
      return error_result("credentials changed during OAuth auth; retry")
    Err(message) => return error_result(message)
  }
  auth_complete_result(server_name)
}

///|
fn save_pending_oauth_flow(
  credentials_path : String,
  server_name~ : String,
  server_url~ : String?,
  client_id~ : String,
  client_secret~ : String?,
  token_endpoint~ : String,
  authorization_issuer~ : String?,
  require_authorization_issuer~ : Bool,
  redirect_uri~ : String,
  code_verifier~ : String,
  state~ : String,
) -> Result[Unit, String] {
  let snapshot = match load_credentials_snapshot_or_empty(credentials_path) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let next = @auth.replace_server_pending_oauth_flow(
    snapshot.file,
    @auth.pending_oauth_flow(
      server_name~,
      server_url~,
      client_id~,
      client_secret~,
      token_endpoint~,
      authorization_issuer~,
      require_authorization_issuer~,
      redirect_uri~,
      code_verifier~,
      state~,
      created_at=current_time_seconds().to_string(),
    ),
  )
  match
    save_credentials_file_if_unchanged(
      credentials_path,
      snapshot.text,
      next,
      error_message="failed to save pending OAuth flow",
    ) {
    Ok(true) => ()
    Ok(false) =>
      return Err("credentials changed while saving pending OAuth flow; retry")
    Err(message) => return Err(message)
  }
  Ok(())
}

///|
fn same_pending_oauth_flow(
  left : @auth.PendingOAuthFlow,
  right : @auth.PendingOAuthFlow,
) -> Bool {
  left.server_name == right.server_name &&
  left.server_url == right.server_url &&
  left.client_info.client_id == right.client_info.client_id &&
  left.client_info.client_secret == right.client_info.client_secret &&
  left.token_endpoint == right.token_endpoint &&
  left.authorization_issuer == right.authorization_issuer &&
  left.require_authorization_issuer == right.require_authorization_issuer &&
  left.redirect_uri == right.redirect_uri &&
  left.code_verifier == right.code_verifier &&
  left.state == right.state &&
  left.created_at == right.created_at
}

///|
fn load_credentials_snapshot_or_empty(
  path : String,
) -> Result[CredentialsSnapshot, String] {
  if @fs.path_exists(path) {
    let text = @fs.read_file_to_string(path) catch {
      _ => return Err("failed to load credentials")
    }
    let json = @json.parse(text) catch {
      _ => return Err("failed to load credentials")
    }
    let file = @auth.decode_credentials_file(json) catch {
      _ => return Err("failed to load credentials")
    }
    Ok({ file, text })
  } else {
    Ok({ file: @auth.empty_credentials_file(), text: "" })
  }
}

///|
fn save_credentials_file_if_unchanged(
  path : String,
  expected_text : String,
  file : @auth.CredentialsFile,
  error_message~ : String,
) -> Result[Bool, String] {
  let current_text = if @fs.path_exists(path) {
    @fs.read_file_to_string(path) catch {
      _ => return Err(error_message)
    }
  } else {
    ""
  }
  if current_text != expected_text {
    return Ok(false)
  }
  @storage.save_credentials_file(path, file) catch {
    _ => return Err(error_message)
  }
  Ok(true)
}

///|
async fn register_oauth_client(
  metadata : @auth.OAuthMetadata,
  redirect_uri : String,
) -> Result[@auth.OAuthClientRegistration, String] {
  let registration_endpoint = match metadata.registration_endpoint {
    Some(value) => value
    None => return Err("OAuth dynamic client registration is unavailable")
  }
  let body = @auth.dynamic_client_registration_request(
    client_name="mcpx",
    redirect_uri~,
  ).stringify()
  let (response, data) = @http.post(registration_endpoint, body, headers={
    "content-type": "application/json",
    "accept": "application/json",
  }) catch {
    _ => return Err("failed to register OAuth client")
  }
  if response.code != 200 && response.code != 201 {
    return Err("failed to register OAuth client")
  }
  let json = data.json() catch {
    _ => return Err("invalid OAuth client registration response")
  }
  match @auth.decode_client_registration_response(json) {
    Ok(value) => Ok(value)
    Err(_) => Err("invalid OAuth client registration response")
  }
}

///|
fn auth_hint_result(hint : @auth.AuthHint) -> String {
  let lines = ["Error: " + hint.summary]
  if !hint.suggested_commands.is_empty() {
    lines.push("")
    lines.push("Try:")
    for command in hint.suggested_commands {
      lines.push("  " + command)
    }
  }
  match hint.config_hint {
    Some(value) => {
      lines.push("")
      lines.push(value)
    }
    None => ()
  }
  lines.join("\n")
}

///|
fn auth_start_result(
  server_name : String,
  authorization_url : String,
  callback_url : String,
  state : String,
) -> String {
  let obj = Map([])
  obj["status"] = Json::string("ok")
  obj["action"] = Json::string("auth")
  obj["server"] = Json::string(server_name)
  obj["authorizationUrl"] = Json::string(authorization_url)
  obj["callbackUrl"] = Json::string(callback_url)
  obj["state"] = Json::string(state)
  obj["noBrowser"] = Json::boolean(true)
  Json::object(obj).stringify()
}

///|
fn auth_complete_result(server_name : String) -> String {
  "Auth complete: " + server_name
}
