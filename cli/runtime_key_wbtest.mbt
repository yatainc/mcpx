///|
test "mcpx runtime: daemon key is secret-free" {
  let server = @config.mcp_server_config(
    name="github",
    transport=Http,
    url=Some(
      "https://user-secret@mcp.github.com/mcp?access_token=url-secret#frag",
    ),
    headers={ "Authorization": "Bearer file-token" },
    env={ "TOKEN": "file-token" },
    auth=Some(
      @config.oauth_server_auth(
        client_id=Some("public-client"),
        client_secret=Some("client-secret"),
        metadata_url=Some("https://auth.example/.well-known/oauth"),
      ),
    ),
  )
  let key = daemon_pool_key_for_test("github", server)
  inspect(key.contains("file-token"), content="false")
  inspect(key.contains("client-secret"), content="false")
  inspect(key.contains("Bearer file-token"), content="false")
  inspect(key.contains("user-secret"), content="false")
  inspect(key.contains("url-secret"), content="false")
  inspect(key.contains("https://mcp.github.com/mcp"), content="true")
  inspect(key.contains("Authorization"), content="true")
  inspect(key.contains("TOKEN"), content="true")
}
