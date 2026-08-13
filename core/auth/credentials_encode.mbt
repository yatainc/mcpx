///|
pub impl ToJson for CredentialsFile with fn to_json(self) {
  let obj = Map([])
  obj["entries"] = credentials_entries_to_json(self.entries)
  obj["version"] = json_int(self.version)
  if self.pending_oauth.length() > 0 {
    obj["pendingOAuth"] = pending_oauth_to_json(self.pending_oauth)
  }
  Json::object(obj)
}

///|
pub impl ToJson for CredentialsEntry with fn to_json(self) {
  let obj = Map([])
  obj["serverName"] = Json::string(self.server_name)
  match self.server_url {
    Some(url) => obj["serverUrl"] = Json::string(url)
    None => ()
  }
  match self.client_info {
    Some(info) => obj["clientInfo"] = info.to_json()
    None => ()
  }
  obj["tokens"] = credentials_tokens_to_json(self.tokens)
  obj["updatedAt"] = Json::string(self.updated_at)
  Json::object(obj)
}

///|
pub impl ToJson for OAuthClientInfo with fn to_json(self) {
  Json::object({ "client_id": Json::string(self.client_id) })
}

///|
pub impl ToJson for OAuthClientSecretInfo with fn to_json(self) {
  let obj = Map([])
  obj["client_id"] = Json::string(self.client_id)
  match self.client_secret {
    Some(value) => obj["client_secret"] = Json::string(value)
    None => ()
  }
  Json::object(obj)
}

///|
pub impl ToJson for PendingOAuthFlow with fn to_json(self) {
  let obj = Map([])
  obj["serverName"] = Json::string(self.server_name)
  match self.server_url {
    Some(value) => obj["serverUrl"] = Json::string(value)
    None => ()
  }
  obj["clientInfo"] = self.client_info.to_json()
  obj["tokenEndpoint"] = Json::string(self.token_endpoint)
  match self.authorization_issuer {
    Some(value) => obj["authorizationIssuer"] = Json::string(value)
    None => ()
  }
  if self.require_authorization_issuer {
    obj["requireAuthorizationIssuer"] = Json::boolean(true)
  }
  obj["redirectUri"] = Json::string(self.redirect_uri)
  obj["codeVerifier"] = Json::string(self.code_verifier)
  obj["state"] = Json::string(self.state)
  obj["createdAt"] = Json::string(self.created_at)
  Json::object(obj)
}

///|
fn credentials_entries_to_json(entries : Map[String, CredentialsEntry]) -> Json {
  let obj = Map([], capacity=entries.length())
  for key, entry in entries {
    obj[key] = entry.to_json()
  }
  Json::object(obj)
}

///|
fn pending_oauth_to_json(flows : Map[String, PendingOAuthFlow]) -> Json {
  let obj = Map([], capacity=flows.length())
  for key, flow in flows {
    obj[key] = flow.to_json()
  }
  Json::object(obj)
}

///|
fn credentials_tokens_to_json(tokens : OAuthTokens) -> Json {
  let obj = Map([])
  obj["access_token"] = Json::string(tokens.access_token)
  match tokens.refresh_token {
    Some(value) => obj["refresh_token"] = Json::string(value)
    None => ()
  }
  obj["token_type"] = Json::string("Bearer")
  match tokens.expires_at {
    Some(value) => obj["expires_at"] = json_int(value)
    None => ()
  }
  Json::object(obj)
}
