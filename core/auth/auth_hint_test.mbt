///|
test "auth hint: 401 suggests explicit auth without opening a browser" {
  let hint = @auth.auth_required_hint(
    server_name="github",
    status_code=401,
    token_env_var=Some("GITHUB_TOKEN"),
  )
  @debug.debug_inspect(
    hint,
    content=(
      #|Some(
      #|  {
      #|    server_name: "github",
      #|    status_code: 401,
      #|    summary: "github returned 401 Unauthorized. Authentication is required.",
      #|    suggested_commands: ["mcpx auth github", "mcpx auth github --no-browser --json"],
      #|    config_hint: Some("headers.Authorization = \"Bearer ${GITHUB_TOKEN}\""),
      #|    opens_browser: false,
      #|  },
      #|)
    ),
  )
}

///|
test "auth hint: 403 suggests auth or scope review" {
  let hint = @auth.auth_required_hint(server_name="github", status_code=403)
  @debug.debug_inspect(
    hint,
    content=(
      #|Some(
      #|  {
      #|    server_name: "github",
      #|    status_code: 403,
      #|    summary: "github returned 403 Forbidden. Token scopes or authorization may be insufficient.",
      #|    suggested_commands: ["mcpx auth github", "mcpx auth github --no-browser --json"],
      #|    config_hint: None,
      #|    opens_browser: false,
      #|  },
      #|)
    ),
  )
}

///|
test "auth hint: non-auth status has no hint" {
  @debug.debug_inspect(
    @auth.auth_required_hint(server_name="github", status_code=500),
    content="None",
  )
}
