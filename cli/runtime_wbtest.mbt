///|
async test "mcpx runtime: no args and --help return help text" {
  let no_args = execute_mcpx([], home="/tmp/mcpx-runtime-test/home")
  let help = execute_mcpx(["--help"], home="/tmp/mcpx-runtime-test/home")
  inspect(
    no_args.contains("mcpx — execute MCP tools via CLI"),
    content="true",
  )
  inspect(no_args.contains("mcpx info <server|url> [tool]"), content="true")
  inspect(help == no_args, content="true")
}

///|
async test "mcpx runtime: --version returns text version" {
  inspect(
    execute_mcpx(["--version"], home="/tmp/mcpx-runtime-test/home"),
    content="mcpx 0.2.0",
  )
}

///|
async test "mcpx runtime: bare commands return command-specific help" {
  inspect(
    execute_mcpx(["call"], home="/tmp/mcpx-runtime-test/home").contains(
      "mcpx call <server|url> <tool>",
    ),
    content="true",
  )
  inspect(
    execute_mcpx(["search"], home="/tmp/mcpx-runtime-test/home").contains(
      "mcpx search <pattern>",
    ),
    content="true",
  )
  inspect(
    execute_mcpx(["auth"], home="/tmp/mcpx-runtime-test/home").contains(
      "mcpx auth <server> [--no-browser] [--json]",
    ),
    content="true",
  )
  inspect(
    execute_mcpx(["daemon"], home="/tmp/mcpx-runtime-test/home").contains(
      "mcpx daemon <status|stop>",
    ),
    content="true",
  )
}

///|
async test "mcpx runtime: removed add command errors" {
  inspect(
    execute_mcpx(
      ["add", "github", "--url", "https://mcp.github.com/mcp"],
      home="/tmp/mcpx-runtime-test/home",
    ),
    content=(
      #|Error: unknown command: add
    ),
  )
}

///|
async test "mcpx runtime: invalid args format error" {
  inspect(
    execute_mcpx(["unknown"], home="/tmp/mcpx-runtime-test/home"),
    content=(
      #|Error: unknown command: unknown
    ),
  )
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: daemon status and stop commands" {
  let home = "/tmp/mcpx-runtime-daemon-command-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.config_dir + "/daemon.json") catch {
    _ => ()
  }
  let stopped = execute_mcpx(["daemon", "status"], home~)
  inspect(stopped, content="Daemon: not running")
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      @mcpx_daemon.run_mcpx_daemon_foreground(home~)
    })
    inspect(wait_for_runtime_daemon(home), content="true")
    let running = execute_mcpx(["daemon", "status"], home~)
    inspect(running, content="Daemon: running")
    let stopped_now = execute_mcpx(["daemon", "stop"], home~)
    inspect(stopped_now, content="Daemon stopped")
  })
}

///|
async fn wait_for_runtime_daemon(home : String) -> Bool {
  for _ in 0..<100 {
    if @mcpx_daemon.daemon_ping(home~) {
      return true
    }
    @async.sleep(20)
  }
  false
}
