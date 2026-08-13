///|
pub struct CredentialsFile {
  version : Int
  entries : Map[String, CredentialsEntry]
  pending_oauth : Map[String, PendingOAuthFlow]
} derive(Debug)

///|
pub struct CredentialsEntry {
  server_name : String
  server_url : String?
  client_info : OAuthClientInfo?
  tokens : OAuthTokens
  updated_at : String
} derive(Debug)

///|
pub struct OAuthClientInfo {
  client_id : String
} derive(Debug)

///|
pub struct OAuthClientSecretInfo {
  client_id : String
  client_secret : String?
} derive(Debug)

///|
pub struct PendingOAuthFlow {
  server_name : String
  server_url : String?
  client_info : OAuthClientSecretInfo
  token_endpoint : String
  authorization_issuer : String?
  require_authorization_issuer : Bool
  redirect_uri : String
  code_verifier : String
  state : String
  created_at : String
} derive(Debug)

///|
suberror CredentialsError {
  InvalidCredentialsJson(String)
} derive(Debug)

///|
pub fn empty_credentials_file() -> CredentialsFile {
  { version: 1, entries: Map([]), pending_oauth: Map([]) }
}

///|
pub fn credentials_entry(
  server_name~ : String,
  server_url? : String? = None,
  client_id? : String? = None,
  access_token~ : String,
  refresh_token? : String? = None,
  expires_at? : Int? = None,
  updated_at~ : String,
) -> CredentialsEntry {
  {
    server_name,
    server_url,
    client_info: client_id.map(id => OAuthClientInfo::{ client_id: id }),
    tokens: oauth_tokens(access_token, refresh_token~, expires_at~),
    updated_at,
  }
}

///|
pub fn put_credentials_entry(
  file : CredentialsFile,
  key : String,
  entry : CredentialsEntry,
) -> CredentialsFile {
  let entries = file.entries.copy()
  entries[key] = entry
  { version: file.version, entries, pending_oauth: file.pending_oauth }
}

///|
pub fn replace_server_credentials_entry(
  file : CredentialsFile,
  key : String,
  entry : CredentialsEntry,
) -> CredentialsFile {
  let entries = Map([], capacity=file.entries.length())
  for existing_key, existing_entry in file.entries {
    if existing_entry.server_name != entry.server_name {
      entries[existing_key] = existing_entry
    }
  }
  entries[key] = entry
  { version: file.version, entries, pending_oauth: file.pending_oauth }
}

///|
pub fn credentials_file_json(file : CredentialsFile) -> String {
  file.to_json().stringify(indent=2) + "\n"
}

///|
pub fn pending_oauth_flow(
  server_name~ : String,
  server_url? : String? = None,
  client_id~ : String,
  client_secret? : String? = None,
  token_endpoint~ : String,
  authorization_issuer? : String? = None,
  require_authorization_issuer? : Bool = false,
  redirect_uri~ : String,
  code_verifier~ : String,
  state~ : String,
  created_at~ : String,
) -> PendingOAuthFlow {
  {
    server_name,
    server_url,
    client_info: { client_id, client_secret },
    token_endpoint,
    authorization_issuer,
    require_authorization_issuer,
    redirect_uri,
    code_verifier,
    state,
    created_at,
  }
}

///|
pub fn put_pending_oauth_flow(
  file : CredentialsFile,
  flow : PendingOAuthFlow,
) -> CredentialsFile {
  let pending_oauth = file.pending_oauth.copy()
  pending_oauth[pending_oauth_key(flow.server_name, flow.state)] = flow
  { version: file.version, entries: file.entries, pending_oauth }
}

///|
pub fn replace_server_pending_oauth_flow(
  file : CredentialsFile,
  flow : PendingOAuthFlow,
) -> CredentialsFile {
  put_pending_oauth_flow(
    remove_server_pending_oauth_flows(file, flow.server_name),
    flow,
  )
}

///|
pub fn find_pending_oauth_flow(
  file : CredentialsFile,
  server_name~ : String,
  state~ : String,
) -> PendingOAuthFlow? {
  file.pending_oauth.get(pending_oauth_key(server_name, state))
}

///|
pub fn remove_pending_oauth_flow(
  file : CredentialsFile,
  server_name~ : String,
  state~ : String,
) -> CredentialsFile {
  let pending_oauth = Map([], capacity=file.pending_oauth.length())
  let target = pending_oauth_key(server_name, state)
  for key, flow in file.pending_oauth {
    if key != target {
      pending_oauth[key] = flow
    }
  }
  { version: file.version, entries: file.entries, pending_oauth }
}

///|
pub fn remove_server_pending_oauth_flows(
  file : CredentialsFile,
  server_name : String,
) -> CredentialsFile {
  let pending_oauth = Map([], capacity=file.pending_oauth.length())
  for key, flow in file.pending_oauth {
    if flow.server_name != server_name {
      pending_oauth[key] = flow
    }
  }
  { version: file.version, entries: file.entries, pending_oauth }
}

///|
fn pending_oauth_key(server_name : String, state : String) -> String {
  server_name + "|" + state
}

///|
pub fn find_credentials_entry(
  file : CredentialsFile,
  server_name~ : String,
  server_url? : String? = None,
) -> CredentialsEntry? {
  match server_url {
    Some(url) =>
      match find_credentials_exact(file, server_name, url) {
        Some(entry) => Some(entry)
        None => find_credentials_by_name(file, server_name)
      }
    None => find_credentials_by_name(file, server_name)
  }
}

///|
fn find_credentials_exact(
  file : CredentialsFile,
  server_name : String,
  server_url : String,
) -> CredentialsEntry? {
  let mut found : CredentialsEntry? = None
  for _, entry in file.entries {
    if entry.server_name == server_name && entry.server_url == Some(server_url) {
      found = newer_credentials_entry(found, entry)
    }
  }
  found
}

///|
fn find_credentials_by_name(
  file : CredentialsFile,
  server_name : String,
) -> CredentialsEntry? {
  let mut found : CredentialsEntry? = None
  for _, entry in file.entries {
    if entry.server_name == server_name {
      found = newer_credentials_entry(found, entry)
    }
  }
  found
}

///|
fn newer_credentials_entry(
  current : CredentialsEntry?,
  candidate : CredentialsEntry,
) -> CredentialsEntry? {
  match current {
    None => Some(candidate)
    Some(value) =>
      if is_newer_credentials_entry(candidate, value) {
        Some(candidate)
      } else {
        Some(value)
      }
  }
}

///|
fn is_newer_credentials_entry(
  candidate : CredentialsEntry,
  current : CredentialsEntry,
) -> Bool {
  let candidate_decimal = is_decimal_timestamp(candidate.updated_at)
  let current_decimal = is_decimal_timestamp(current.updated_at)
  if candidate_decimal && current_decimal {
    compare_decimal_timestamp(candidate.updated_at, current.updated_at) > 0
  } else if candidate_decimal {
    true
  } else if current_decimal {
    false
  } else {
    compare_text_timestamp(candidate.updated_at, current.updated_at) > 0
  }
}

///|
fn is_decimal_timestamp(text : String) -> Bool {
  if text.is_empty() {
    return false
  }
  for c in text.to_array() {
    if c < '0' || c > '9' {
      return false
    }
  }
  true
}

///|
fn compare_decimal_timestamp(left : String, right : String) -> Int {
  let left_chars = left.to_array()
  let right_chars = right.to_array()
  let left_start = first_significant_decimal_index(left_chars)
  let right_start = first_significant_decimal_index(right_chars)
  let left_length = left_chars.length() - left_start
  let right_length = right_chars.length() - right_start
  if left_length != right_length {
    if left_length > right_length {
      return 1
    } else {
      return -1
    }
  }
  for offset in 0..<left_length {
    let left_char = left_chars[left_start + offset]
    let right_char = right_chars[right_start + offset]
    if left_char != right_char {
      return compare_char(left_char, right_char)
    }
  }
  0
}

///|
fn first_significant_decimal_index(chars : Array[Char]) -> Int {
  let mut index = 0
  while index < chars.length() - 1 && chars[index] == '0' {
    index = index + 1
  }
  index
}

///|
fn compare_text_timestamp(left : String, right : String) -> Int {
  if left == right {
    0
  } else if left > right {
    1
  } else {
    -1
  }
}

///|
fn compare_char(left : Char, right : Char) -> Int {
  if left == right {
    0
  } else if left > right {
    1
  } else {
    -1
  }
}

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

///|
pub fn decode_credentials_file(
  json : Json,
) -> CredentialsFile raise CredentialsError {
  let obj = expect_object(json, "credentials file")
  let version = expect_int(obj.get("version"), "version")
  let entries_json = expect_object_option(obj.get("entries"), "entries")
  let entries = Map([], capacity=entries_json.length())
  for key, value in entries_json {
    entries[key] = decode_credentials_entry(value)
  }
  let pending_oauth_json = optional_object_map(obj.get("pendingOAuth"))
  let pending_oauth = Map([], capacity=pending_oauth_json.length())
  for key, value in pending_oauth_json {
    pending_oauth[key] = decode_pending_oauth_flow(value)
  }
  { version, entries, pending_oauth }
}

///|
fn decode_credentials_entry(
  json : Json,
) -> CredentialsEntry raise CredentialsError {
  let obj = expect_object(json, "credentials entry")
  {
    server_name: expect_string(obj.get("serverName"), "serverName"),
    server_url: optional_string(obj.get("serverUrl"), "serverUrl"),
    client_info: optional_client_info(obj.get("clientInfo")),
    tokens: decode_tokens(obj.get("tokens")),
    updated_at: expect_string(obj.get("updatedAt"), "updatedAt"),
  }
}

///|
fn optional_client_info(
  json : Json?,
) -> OAuthClientInfo? raise CredentialsError {
  match json {
    None | Some(Null) => None
    Some(value) => {
      let obj = expect_object(value, "clientInfo")
      Some({ client_id: expect_string(obj.get("client_id"), "client_id") })
    }
  }
}

///|
fn decode_pending_oauth_flow(
  json : Json,
) -> PendingOAuthFlow raise CredentialsError {
  let obj = expect_object(json, "pending OAuth flow")
  {
    server_name: expect_string(obj.get("serverName"), "serverName"),
    server_url: optional_string(obj.get("serverUrl"), "serverUrl"),
    client_info: decode_client_secret_info(obj.get("clientInfo")),
    token_endpoint: expect_string(obj.get("tokenEndpoint"), "tokenEndpoint"),
    authorization_issuer: optional_string(
      obj.get("authorizationIssuer"),
      "authorizationIssuer",
    ),
    require_authorization_issuer: optional_bool(
      obj.get("requireAuthorizationIssuer"),
      "requireAuthorizationIssuer",
    ),
    redirect_uri: expect_string(obj.get("redirectUri"), "redirectUri"),
    code_verifier: expect_string(obj.get("codeVerifier"), "codeVerifier"),
    state: expect_string(obj.get("state"), "state"),
    created_at: expect_string(obj.get("createdAt"), "createdAt"),
  }
}

///|
fn decode_client_secret_info(
  json : Json?,
) -> OAuthClientSecretInfo raise CredentialsError {
  let obj = expect_object_option(json, "clientInfo")
  {
    client_id: expect_string(obj.get("client_id"), "client_id"),
    client_secret: optional_string(obj.get("client_secret"), "client_secret"),
  }
}

///|
fn decode_tokens(json : Json?) -> OAuthTokens raise CredentialsError {
  let obj = expect_object_option(json, "tokens")
  oauth_tokens(
    expect_string(obj.get("access_token"), "access_token"),
    refresh_token=optional_string(obj.get("refresh_token"), "refresh_token"),
    expires_at=optional_int(obj.get("expires_at"), "expires_at"),
  )
}

///|
fn expect_object(
  json : Json,
  context : String,
) -> Map[String, Json] raise CredentialsError {
  match json {
    Object(obj) => obj
    _ =>
      raise CredentialsError::InvalidCredentialsJson(
        context + " must be object",
      )
  }
}

///|
fn expect_object_option(
  json : Json?,
  field : String,
) -> Map[String, Json] raise CredentialsError {
  match json {
    Some(Object(obj)) => obj
    _ =>
      raise CredentialsError::InvalidCredentialsJson(field + " must be object")
  }
}

///|
fn optional_object_map(
  json : Json?,
) -> Map[String, Json] raise CredentialsError {
  match json {
    None | Some(Null) => Map([])
    Some(Object(obj)) => obj
    _ =>
      raise CredentialsError::InvalidCredentialsJson(
        "pendingOAuth must be object",
      )
  }
}

///|
fn expect_string(json : Json?, field : String) -> String raise CredentialsError {
  match json {
    Some(String(value)) => value
    _ =>
      raise CredentialsError::InvalidCredentialsJson(field + " must be string")
  }
}

///|
fn optional_string(
  json : Json?,
  field : String,
) -> String? raise CredentialsError {
  match json {
    None | Some(Null) => None
    Some(String(value)) => Some(value)
    _ =>
      raise CredentialsError::InvalidCredentialsJson(field + " must be string")
  }
}

///|
fn optional_bool(json : Json?, field : String) -> Bool raise CredentialsError {
  match json {
    None | Some(Null) | Some(False) => false
    Some(True) => true
    _ => raise CredentialsError::InvalidCredentialsJson(field + " must be bool")
  }
}

///|
fn expect_int(json : Json?, field : String) -> Int raise CredentialsError {
  match json {
    Some(Number(value, ..)) if value.trunc() == value => value.to_int()
    _ => raise CredentialsError::InvalidCredentialsJson(field + " must be int")
  }
}

///|
fn optional_int(json : Json?, field : String) -> Int? raise CredentialsError {
  match json {
    None | Some(Null) => None
    Some(Number(value, ..)) if value.trunc() == value => Some(value.to_int())
    _ => raise CredentialsError::InvalidCredentialsJson(field + " must be int")
  }
}

///|
fn json_int(value : Int) -> Json {
  Json::number(Double::from_int(value), repr=value.to_string())
}
