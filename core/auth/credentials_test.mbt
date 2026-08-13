///|
fn alphaxiv_entry(
  client_id : String,
  access_token : String,
  updated_at : String,
) -> CredentialsEntry {
  credentials_entry(
    server_name="alphaxiv",
    server_url=Some("https://api.alphaxiv.org/mcp/v1"),
    client_id=Some(client_id),
    access_token~,
    updated_at~,
  )
}

///|
fn test_pending_flow(
  server_name : String,
  client_id : String,
  state : String,
) -> PendingOAuthFlow {
  pending_oauth_flow(
    server_name~,
    client_id~,
    token_endpoint="https://auth.example/token",
    redirect_uri="http://127.0.0.1:8765/callback",
    code_verifier=client_id + "-verifier",
    state~,
    created_at="1000",
  )
}

///|
test "credentials: empty file encodes version and entries" {
  inspect(
    empty_credentials_file().to_json().stringify(),
    content="{\"entries\":{},\"version\":1}",
  )
}

///|
test "credentials: stores server entry keyed by name and transport hash" {
  let file = empty_credentials_file()
  let entry = credentials_entry(
    server_name="github",
    server_url=Some("https://mcp.github.com/mcp"),
    client_id=Some("client-1"),
    access_token="access-1",
    refresh_token=Some("refresh-1"),
    expires_at=Some(2000),
    updated_at="2026-05-16T00:00:00.000Z",
  )
  let next = put_credentials_entry(file, "github|abcd", entry)
  inspect(
    next.to_json().stringify(),
    content=(
      #|{"entries":{"github|abcd":{"serverName":"github","serverUrl":"https://mcp.github.com/mcp","clientInfo":{"client_id":"client-1"},"tokens":{"access_token":"access-1","refresh_token":"refresh-1","token_type":"Bearer","expires_at":2000},"updatedAt":"2026-05-16T00:00:00.000Z"}},"version":1}
    ),
  )
}

///|
test "credentials: decodes encoded file roundtrip" {
  let file = put_credentials_entry(
    empty_credentials_file(),
    "github|abcd",
    credentials_entry(
      server_name="github",
      server_url=Some("https://mcp.github.com/mcp"),
      client_id=Some("client-1"),
      access_token="access-1",
      refresh_token=Some("refresh-1"),
      expires_at=Some(2000),
      updated_at="2026-05-16T00:00:00.000Z",
    ),
  )
  let decoded = decode_credentials_file(file.to_json())
  @debug.debug_inspect(
    decoded,
    content=(
      #|{
      #|  version: 1,
      #|  entries: {
      #|    "github|abcd": {
      #|      server_name: "github",
      #|      server_url: Some("https://mcp.github.com/mcp"),
      #|      client_info: Some({ client_id: "client-1" }),
      #|      tokens: {
      #|        access_token: "access-1",
      #|        refresh_token: Some("refresh-1"),
      #|        expires_at: Some(2000),
      #|      },
      #|      updated_at: "2026-05-16T00:00:00.000Z",
      #|    },
      #|  },
      #|  pending_oauth: {},
      #|}
    ),
  )
}

///|
test "credentials: finds entry by server name and exact url before fallback" {
  let file = put_credentials_entry(
    empty_credentials_file(),
    "github|old",
    credentials_entry(
      server_name="github",
      server_url=Some("https://old.example/mcp"),
      access_token="old-token",
      updated_at="2026-05-16T00:00:00.000Z",
    ),
  )
  let file = put_credentials_entry(
    file,
    "github|current",
    credentials_entry(
      server_name="github",
      server_url=Some("https://mcp.github.com/mcp"),
      access_token="current-token",
      updated_at="2026-05-16T00:00:00.000Z",
    ),
  )
  let token = match
    find_credentials_entry(
      file,
      server_name="github",
      server_url=Some("https://mcp.github.com/mcp"),
    ) {
    Some(entry) => entry.tokens.access_token
    None => "missing"
  }
  inspect(token, content="current-token")
}

///|
test "credentials: finds latest matching entry with long decimal updatedAt" {
  let file = put_credentials_entry(
    empty_credentials_file(),
    "alphaxiv|old-client",
    alphaxiv_entry("old-client", "old-token", "999999999999999999999999999998"),
  )
  let file = put_credentials_entry(
    file,
    "alphaxiv|new-client",
    alphaxiv_entry("new-client", "new-token", "999999999999999999999999999999"),
  )
  let token = match
    find_credentials_entry(
      file,
      server_name="alphaxiv",
      server_url=Some("https://api.alphaxiv.org/mcp/v1"),
    ) {
    Some(entry) => entry.tokens.access_token
    None => "missing"
  }
  inspect(token, content="new-token")
}

///|
test "credentials: replacing server entry prunes older server credentials" {
  let file = put_credentials_entry(
    empty_credentials_file(),
    "github|client-1",
    credentials_entry(
      server_name="github",
      server_url=Some("https://mcp.github.com/mcp"),
      client_id=Some("client-1"),
      access_token="github-token",
      updated_at="100",
    ),
  )
  let file = put_credentials_entry(
    file,
    "alphaxiv|old-client",
    alphaxiv_entry("old-client", "old-token", "100"),
  )
  let next = replace_server_credentials_entry(
    file,
    "alphaxiv|new-client",
    alphaxiv_entry("new-client", "new-token", "200"),
  )
  inspect(next.entries.length(), content="2")
  inspect(next.entries.contains("alphaxiv|old-client"), content="false")
  inspect(next.entries.contains("alphaxiv|new-client"), content="true")
  inspect(next.entries.contains("github|client-1"), content="true")
}

///|
test "credentials: stores pending OAuth flow by server and state" {
  let file = put_pending_oauth_flow(
    empty_credentials_file(),
    pending_oauth_flow(
      server_name="github",
      server_url=Some("https://mcp.github.com/mcp"),
      client_id="client-1",
      client_secret=Some("secret-1"),
      token_endpoint="https://auth.example/token",
      authorization_issuer=Some("https://auth.example"),
      require_authorization_issuer=true,
      redirect_uri="http://127.0.0.1:8765/callback",
      code_verifier="verifier-1",
      state="state-1",
      created_at="1000",
    ),
  )
  inspect(
    file.to_json().stringify(),
    content=(
      #|{"entries":{},"version":1,"pendingOAuth":{"github|state-1":{"serverName":"github","serverUrl":"https://mcp.github.com/mcp","clientInfo":{"client_id":"client-1","client_secret":"secret-1"},"tokenEndpoint":"https://auth.example/token","authorizationIssuer":"https://auth.example","requireAuthorizationIssuer":true,"redirectUri":"http://127.0.0.1:8765/callback","codeVerifier":"verifier-1","state":"state-1","createdAt":"1000"}}}
    ),
  )
  let decoded = decode_credentials_file(file.to_json())
  let found = find_pending_oauth_flow(
    decoded,
    server_name="github",
    state="state-1",
  )
  @debug.debug_inspect(
    found.map(flow => (flow.client_info.client_id, flow.code_verifier)),
    content=(
      #|Some(("client-1", "verifier-1"))
    ),
  )
}

///|
test "credentials: replacing server pending OAuth flow prunes older server flows" {
  let file = put_pending_oauth_flow(
    empty_credentials_file(),
    test_pending_flow("github", "github-client", "github-state"),
  )
  let file = put_pending_oauth_flow(
    file,
    test_pending_flow("alphaxiv", "old-client", "old-state"),
  )
  let next = replace_server_pending_oauth_flow(
    file,
    test_pending_flow("alphaxiv", "new-client", "new-state"),
  )
  inspect(next.pending_oauth.length(), content="2")
  inspect(next.pending_oauth.contains("alphaxiv|old-state"), content="false")
  inspect(next.pending_oauth.contains("alphaxiv|new-state"), content="true")
  inspect(next.pending_oauth.contains("github|github-state"), content="true")
}

///|
test "credentials: removes pending OAuth flow after exchange" {
  let file = put_pending_oauth_flow(
    empty_credentials_file(),
    test_pending_flow("github", "client-1", "state-1"),
  )
  let next = remove_pending_oauth_flow(
    file,
    server_name="github",
    state="state-1",
  )
  inspect(next.to_json().stringify(), content="{\"entries\":{},\"version\":1}")
}
