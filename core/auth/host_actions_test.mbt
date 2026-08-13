///|
test "auth host actions: first step reads credentials file" {
  let action = credentials_lookup_action(
    credentials_path="/home/me/.config/mcpx/credentials.json",
  )
  inspect(
    action.to_json().stringify(),
    content=(
      #|{"kind":"read_text_file","path":"/home/me/.config/mcpx/credentials.json"}
    ),
  )
}

///|
test "auth host actions: stores refreshed credentials with private atomic write" {
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
  let action = credentials_write_action(
    credentials_path="/home/me/.config/mcpx/credentials.json",
    file,
  )
  match action {
    WriteTextFile(write) => {
      inspect(write.path, content="/home/me/.config/mcpx/credentials.json")
      inspect(write.contents.contains("\n  \"entries\""), content="true")
      inspect(write.contents.has_suffix("\n"), content="true")
      inspect(write.mode, content="384")
      inspect(write.atomic_write, content="true")
      inspect(write.create_parent_dirs, content="true")
    }
    _ => inspect("unexpected action", content="write action")
  }
}

///|
test "auth host actions: cached valid token becomes bearer header" {
  let entry = credentials_entry(
    server_name="github",
    access_token="access-1",
    refresh_token=Some("refresh-1"),
    expires_at=Some(2000),
    updated_at="2026-05-16T00:00:00.000Z",
  )
  @debug.debug_inspect(
    decide_auth_cache(Some(entry), now_seconds=1000, skew_seconds=300),
    content="UseBearerHeader(\"Bearer access-1\")",
  )
}

///|
test "auth host actions: near-expiry token with refresh token requests refresh" {
  let entry = credentials_entry(
    server_name="github",
    access_token="access-1",
    refresh_token=Some("refresh-1"),
    expires_at=Some(1200),
    updated_at="2026-05-16T00:00:00.000Z",
  )
  @debug.debug_inspect(
    decide_auth_cache(Some(entry), now_seconds=1000, skew_seconds=300),
    content="RefreshWithToken(\"refresh-1\")",
  )
}

///|
test "auth host actions: missing cache requires explicit auth" {
  @debug.debug_inspect(
    decide_auth_cache(None, now_seconds=1000, skew_seconds=300),
    content="ReauthRequired",
  )
}
