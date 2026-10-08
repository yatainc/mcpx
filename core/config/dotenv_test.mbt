///|
test "dotenv: parses comments blanks and simple assignments" {
  let text =
    #|# mcpx local secrets
    #|GITHUB_TOKEN=token-1
    #|
    #|GITHUB_CLIENT_ID=client-1
    #|GITHUB_CLIENT_SECRET="secret with spaces"
  @debug.debug_inspect(
    @config.parse_dotenv(text),
    content=(
      #|Ok(
      #|  {
      #|    "GITHUB_TOKEN": "token-1",
      #|    "GITHUB_CLIENT_ID": "client-1",
      #|    "GITHUB_CLIENT_SECRET": "secret with spaces",
      #|  },
      #|)
    ),
  )
}

///|
test "dotenv: process env overrides file env when merged" {
  let file_env = @config.parse_dotenv("GITHUB_TOKEN=file\nLOCAL_ONLY=yes")
  let process_env = { "GITHUB_TOKEN": "process" }
  @debug.debug_inspect(
    @config.merge_env(file_env.unwrap(), process_env),
    content=(
      #|{ "GITHUB_TOKEN": "process", "LOCAL_ONLY": "yes" }
    ),
  )
}

///|
test "dotenv: invalid key is rejected" {
  @debug.debug_inspect(
    @config.parse_dotenv("1BAD=value"),
    content="Err(InvalidDotenvLine(1, \"1BAD=value\"))",
  )
}
