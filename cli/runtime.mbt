///|
pub fn run_mcpx_args(
  args : Array[String],
  home~ : String,
  config_home? : String? = None,
) -> String {
  ignore(home)
  ignore(config_home)
  match parse_mcpx_args(args) {
    Err(error) => error_result(format_mcpx_parse_error(error))
    Ok(command) => run_mcpx_command(command)
  }
}

///|
pub fn run_mcpx_args_with_stdin(
  args : Array[String],
  home~ : String,
  config_home? : String? = None,
  stdin_json? : String? = None,
) -> String {
  ignore(home)
  ignore(config_home)
  ignore(stdin_json)
  match parse_mcpx_args(args) {
    Err(error) => error_result(format_mcpx_parse_error(error))
    Ok(command) => run_mcpx_command(command)
  }
}

///|
pub fn run_mcpx_command(command : McpxCommand) -> String {
  render_mcpx_command(command)
}

///|
fn error_result(message : String) -> String {
  "Error: " + message
}

///|
pub async fn run_mcpx_args_async(
  args : Array[String],
  home~ : String,
  config_home? : String? = None,
) -> String {
  run_mcpx_args_async_with_stdin(args, home~, config_home~, stdin_json=None)
}

///|
pub async fn run_mcpx_args_async_with_stdin(
  args : Array[String],
  home~ : String,
  config_home? : String? = None,
  stdin_json? : String? = None,
) -> String {
  match parse_mcpx_args(args) {
    Err(error) => error_result(format_mcpx_parse_error(error))
    Ok(command) =>
      run_mcpx_command_async(command, home~, config_home~, stdin_json~)
  }
}

///|
async fn run_mcpx_command_async(
  command : McpxCommand,
  home~ : String,
  config_home? : String? = None,
  stdin_json? : String? = None,
) -> String {
  match command {
    Call(call) => run_call(call, home, config_home, stdin_json~)
    Info(info) => run_info(info, home, config_home)
    Search(search) => run_search(search, home, config_home)
    Auth(auth) => run_auth(auth, home, config_home)
    Daemon(daemon) => run_daemon(daemon, home, config_home)
    _ => run_mcpx_command(command)
  }
}
