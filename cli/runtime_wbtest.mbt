///|
test "mcpx runtime: no args and --help return help text" {
  let no_args = run_mcpx_args([], home="/tmp/mcpx-runtime-test/home")
  let help = run_mcpx_args(["--help"], home="/tmp/mcpx-runtime-test/home")
  inspect(
    no_args.contains("mcpx — execute MCP tools via CLI"),
    content="true",
  )
  inspect(no_args.contains("mcpx info <server|url> [tool]"), content="true")
  inspect(help == no_args, content="true")
}

///|
test "mcpx runtime: --version returns text version" {
  inspect(
    run_mcpx_args(["--version"], home="/tmp/mcpx-runtime-test/home"),
    content="mcpx 0.2.0",
  )
}

///|
test "mcpx runtime: bare commands return command-specific help" {
  inspect(
    run_mcpx_args(["call"], home="/tmp/mcpx-runtime-test/home").contains(
      "mcpx call <server|url> <tool>",
    ),
    content="true",
  )
  inspect(
    run_mcpx_args(["search"], home="/tmp/mcpx-runtime-test/home").contains(
      "mcpx search <pattern>",
    ),
    content="true",
  )
  inspect(
    run_mcpx_args(["auth"], home="/tmp/mcpx-runtime-test/home").contains(
      "mcpx auth <server> [--no-browser] [--json]",
    ),
    content="true",
  )
  inspect(
    run_mcpx_args(["daemon"], home="/tmp/mcpx-runtime-test/home").contains(
      "mcpx daemon <status|stop>",
    ),
    content="true",
  )
}

///|
test "mcpx runtime: removed add command errors" {
  inspect(
    run_mcpx_args(
      ["add", "github", "--url", "https://mcp.github.com/mcp"],
      home="/tmp/mcpx-runtime-test/home",
    ),
    content=(
      #|Error: unknown command: add
    ),
  )
}

///|
test "mcpx runtime: invalid args format error" {
  inspect(
    run_mcpx_args(["unknown"], home="/tmp/mcpx-runtime-test/home"),
    content=(
      #|Error: unknown command: unknown
    ),
  )
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: daemon status and stop commands" {
  let home = "/tmp/mcpx-runtime-daemon-command-test/home"
  @fs.remove_file(@mcpx_daemon.mcpx_daemon_state_path(home~)) catch {
    _ => ()
  }
  let stopped = run_mcpx_args_async(["daemon", "status"], home~)
  inspect(stopped, content="Daemon: not running")
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      @mcpx_daemon.run_mcpx_daemon_foreground(home~)
    })
    let port = wait_for_runtime_test_daemon_port(home)
    inspect(port > 0, content="true")
    let running = run_mcpx_args_async(["daemon", "status"], home~)
    inspect(running, content="Daemon: running")
    let stopped_now = run_mcpx_args_async(["daemon", "stop"], home~)
    inspect(stopped_now, content="Daemon stopped")
  })
}

///|
async fn wait_for_runtime_test_daemon_port(home : String) -> Int {
  for i in 0..<100 {
    ignore(i)
    match @mcpx_daemon.read_mcpx_daemon_port(home~) {
      Some(port) => break port
      None => @async.sleep(20)
    }
  } nobreak {
    0
  }
}
