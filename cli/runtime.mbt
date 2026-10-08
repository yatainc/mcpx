///|
fn error_result(message : String) -> String {
  "Error: " + message
}

///|
async fn execute_mcpx(
  args : Array[String],
  home~ : String,
  config_home? : String? = None,
  stdin_json? : String? = None,
) -> String {
  let command = match parse_mcpx_args(args) {
    Err(error) => return error_result(format_mcpx_parse_error(error))
    Ok(command) => command
  }
  match command {
    Help => mcpx_help_text()
    Version => "mcpx " + @protocol.MCPX_CLIENT_VERSION
    CallHelp => call_help_text()
    Call(call) => run_call(call, home, config_home, stdin_json~)
    Info(info) => run_info(info, home, config_home)
    SearchHelp => search_help_text()
    Search(search) => run_search(search, home, config_home)
    AuthHelp => auth_help_text()
    Auth(auth) => run_auth(auth, home, config_home)
    Daemon(daemon) => run_daemon(daemon, home, config_home)
  }
}
