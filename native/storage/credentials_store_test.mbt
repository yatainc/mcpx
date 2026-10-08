///|
test "credentials store: missing file loads empty credentials" {
  let path = "/tmp/mcpx-credentials-store-test/missing/credentials.json"
  @fs.remove_file(path) catch {
    _ => ()
  }
  inspect(
    @storage.load_credentials_file_or_empty(path).to_json().stringify(),
    content="{\"entries\":{},\"version\":1}",
  )
}

///|
test "credentials store: save uses secure write and can load roundtrip" {
  let path = "/tmp/mcpx-credentials-store-test/nested/credentials.json"
  @fs.remove_file(path) catch {
    _ => ()
  }
  let file = @auth.put_credentials_entry(
    @auth.empty_credentials_file(),
    "github|abcd",
    @auth.credentials_entry(
      server_name="github",
      server_url=Some("https://mcp.github.com/mcp"),
      client_id=Some("client-1"),
      access_token="access-1",
      refresh_token=Some("refresh-1"),
      expires_at=Some(2000),
      updated_at="2026-05-16T00:00:00.000Z",
    ),
  )
  @storage.save_credentials_file(path, file)
  let saved = @fs.read_file_to_string(path)
  inspect(saved.contains("\n  \"entries\""), content="true")
  inspect(saved.has_suffix("\n"), content="true")
  inspect(@storage.credentials_file_mode(path), content="384")
  inspect(
    @storage.load_credentials_file_or_empty(path).to_json().stringify(),
    content=(
      #|{"entries":{"github|abcd":{"serverName":"github","serverUrl":"https://mcp.github.com/mcp","clientInfo":{"client_id":"client-1"},"tokens":{"access_token":"access-1","refresh_token":"refresh-1","token_type":"Bearer","expires_at":2000},"updatedAt":"2026-05-16T00:00:00.000Z"}},"version":1}
    ),
  )
}
