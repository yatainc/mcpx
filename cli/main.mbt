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
  let stdin_json = read_piped_stdin()
  let output = run_mcpx_args_async_with_stdin(
    args,
    home~,
    config_home~,
    stdin_json~,
  ) catch {
    err => {
      let message = err.to_string()
      "Error: " + message
    }
  }
  println(output)
  if output.has_prefix("Error:") || output.has_prefix("{\"status\":\"error\"") {
    @sys.exit(2)
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
