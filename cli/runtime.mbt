///|
fn error_result(message : String) -> String {
  "Error: " + message
}

///|
async fn execute_command(
  command : McpxCommand,
  home~ : String,
  config_home? : String? = None,
  stdin_json? : String? = None,
) -> Result[String, String] {
  let output = match command {
    Help => mcpx_help_text()
    Version => "mcpx " + @protocol.MCPX_CLIENT_VERSION
    CallHelp => call_help_text()
    Call(call) => run_call(call, home, config_home, stdin_json~)
    Info(info) => run_info(info, home, config_home)
    SkillsHelp => skills_help_text()
    ResourcesHelp => resources_help_text()
    Retrieve(command) => return Ok(run_retrieval(command, home, config_home))
    SearchHelp => search_help_text()
    Search(search) => run_search(search, home, config_home)
    AuthHelp => auth_help_text()
    Auth(auth) => run_auth(auth, home, config_home)
    Daemon(daemon) => run_daemon(daemon, home, config_home)
  }
  if output.has_prefix("Error:") || output.has_prefix("{\"status\":\"error\"") {
    Err(output)
  } else {
    Ok(output)
  }
}
