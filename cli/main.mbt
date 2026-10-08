///|
fn main {
  @async.run_async_main(() => run())
}

///|
async fn run() -> Unit {
  let argv = @env.args()
  let args = if argv.is_empty() { [] } else { argv[1:].to_owned() }
  let home = @env.get_env_var("HOME").unwrap_or(".")
  let config_home = @env.get_env_var("XDG_CONFIG_HOME")
  if @env.get_env_var("MCPX_INTERNAL_DAEMON") == Some("serve") {
    run_internal_daemon_async(home~, config_home~)
    return
  }
  let command = match parse_mcpx_args(args) {
    Ok(command) => command
    Err(error) => {
      println(error_result(format_mcpx_parse_error(error)))
      @sys.exit(2)
      return
    }
  }
  let stdin_json = match command {
    Call(_) => read_piped_stdin()
    _ => None
  }
  let result = execute_command(command, home~, config_home~, stdin_json~) catch {
    @skill_cli.RetrievalError(message) => Err(error_result(message))
    @async.TimeoutError => Err(error_result("MCP operation timed out"))
    error => Err(error_result(error.to_string()))
  }
  match result {
    Ok(output) => println(output)
    Err(message) => {
      println(message)
      @sys.exit(2)
    }
  }
}

///|
fn read_piped_stdin() -> String? {
  let path = "/dev/stdin"
  let is_stdin_file = @fs.is_file(path) catch { _ => false }
  if !is_stdin_file {
    return None
  }
  let text = @fs.read_file_to_string(path) catch { _ => return None }
  if text.trim().is_empty() {
    None
  } else {
    Some(text)
  }
}
