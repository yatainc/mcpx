///|
async fn run_daemon(
  command : DaemonCommand,
  home : String,
  config_home : String?,
) -> String {
  match command.mode {
    Help => run_mcpx_command(Daemon(command))
    Status => {
      let running = @mcpx_daemon.daemon_ping(home~, config_home~) catch {
        _ => false
      }
      daemon_result("status", running~)
    }
    Stop => {
      let stopped = @mcpx_daemon.daemon_stop(home~, config_home~) catch {
        _ => false
      }
      daemon_stop_result(stopped)
    }
  }
}

///|
pub async fn run_internal_daemon_async(
  home~ : String,
  config_home? : String? = None,
) -> Unit {
  @mcpx_daemon.run_mcpx_daemon_foreground(home~, config_home~)
}

///|
fn daemon_result(action : String, running~ : Bool) -> String {
  ignore(action)
  if running {
    "Daemon: running"
  } else {
    "Daemon: not running"
  }
}

///|
fn daemon_stop_result(stopped : Bool) -> String {
  if stopped {
    "Daemon stopped"
  } else {
    "Daemon not running"
  }
}
