///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: call uses configured stdio server" {
  let home = "/tmp/mcpx-runtime-stdio-call-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.servers_config) catch {
    _ => ()
  }
  @storage.save_mcpx_config_file(
    paths.servers_config,
    @config.put_server_config(
      @config.empty_mcpx_config(),
      @config.mcp_server_config(
        name="local",
        transport=Stdio,
        command=Some("/bin/sh"),
        args=["-c", stdio_call_script()],
      ),
    ),
  )
  let result = run_mcpx_args_async(
    ["call", "local", "search", "{\"q\":\"moonbit\"}"],
    home~,
  )
  inspect(
    result,
    content=(
      #|Result:
      #|{"ok":true,"transport":"stdio"}
    ),
  )
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: info uses configured stdio server" {
  let home = "/tmp/mcpx-runtime-stdio-list-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.servers_config) catch {
    _ => ()
  }
  @storage.save_mcpx_config_file(
    paths.servers_config,
    @config.put_server_config(
      @config.empty_mcpx_config(),
      @config.mcp_server_config(
        name="local",
        transport=Stdio,
        command=Some("/bin/sh"),
        args=["-c", stdio_list_script()],
      ),
    ),
  )
  let result = run_mcpx_args_async(["info", "local"], home~)
  inspect(
    result,
    content=(
      #|Tools
      #|  search()
      #|    Search things
    ),
  )
}

///|
fn stdio_call_script() -> String {
  (
    #|i=0
    #|while IFS= read -r line; do
    #|  i=$((i + 1))
    #|  if [ "$i" = "1" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-03-26","capabilities":{},"serverInfo":{"name":"srv"}}}'
    #|  elif [ "$i" = "3" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"ok":true,"transport":"stdio"}}'
    #|  fi
    #|done
  )
}

///|
fn stdio_list_script() -> String {
  (
    #|i=0
    #|while IFS= read -r line; do
    #|  i=$((i + 1))
    #|  if [ "$i" = "1" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-03-26","capabilities":{},"serverInfo":{"name":"srv"}}}'
    #|  elif [ "$i" = "3" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"search","description":"Search things","inputSchema":{"type":"object"}}]}}'
    #|  fi
    #|done
  )
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: stdio resolves .env into env args and cwd" {
  let home = "/tmp/mcpx-runtime-stdio-env-cwd-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.servers_config) catch {
    _ => ()
  }
  @fs.remove_file(paths.env_file) catch {
    _ => ()
  }
  @storage.save_mcpx_config_file(
    paths.servers_config,
    @config.put_server_config(
      @config.empty_mcpx_config(),
      @config.mcp_server_config(
        name="local",
        transport=Stdio,
        command=Some("/bin/sh"),
        args=["-c", stdio_env_cwd_script()],
        env={ "EXPECTED_TOKEN": "${EXPECTED_TOKEN}" },
        cwd=Some("${EXPECTED_CWD}"),
      ),
    ),
  )
  @fs.write_string_to_file(
    paths.env_file,
    "EXPECTED_TOKEN=secret-token\nEXPECTED_CWD=/\n",
  )
  let result = run_mcpx_args_async(["call", "local", "check", "{}"], home~)
  inspect(result, content="Result:\n{\"ok\":true}")
}

///|
fn stdio_env_cwd_script() -> String {
  (
    #|i=0
    #|while IFS= read -r line; do
    #|  i=$((i + 1))
    #|  if [ "$i" = "1" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-03-26","capabilities":{},"serverInfo":{"name":"srv"}}}'
    #|  elif [ "$i" = "3" ]; then
    #|    if [ "$EXPECTED_TOKEN" = "secret-token" ] && [ "$(pwd)" = "${EXPECTED_CWD}" ]; then
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"ok":true}}'
    #|    else
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"ok":false}}'
    #|    fi
    #|  fi
    #|done
  )
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx runtime: keep-alive stdio calls are routed through daemon" {
  let home = "/tmp/mcpx-runtime-keepalive-daemon-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.servers_config) catch {
    _ => ()
  }
  @fs.remove_file(@mcpx_daemon.mcpx_daemon_state_path(home~)) catch {
    _ => ()
  }
  @storage.save_mcpx_config_file(
    paths.servers_config,
    @config.put_server_config(
      @config.empty_mcpx_config(),
      @config.mcp_server_config(
        name="local",
        transport=Stdio,
        command=Some("/bin/sh"),
        args=["-c", stdio_keepalive_script()],
        lifecycle=Some(@config.server_lifecycle(KeepAlive)),
      ),
    ),
  )
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      @mcpx_daemon.run_mcpx_daemon_foreground(home~)
    })
    let port = wait_for_runtime_daemon_port(home)
    inspect(port > 0, content="true")
    let first = run_mcpx_args_async(["call", "local", "count", "{}"], home~)
    let second = run_mcpx_args_async(["call", "local", "count", "{}"], home~)
    inspect(
      first + "|" + second,
      content=(
        #|Result:
        #|{"call":1}|Result:
        #|{"call":2}
      ),
    )
    ignore(@mcpx_daemon.daemon_stop(home~))
  })
}

///|
async fn wait_for_runtime_daemon_port(home : String) -> Int {
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

///|
fn stdio_keepalive_script() -> String {
  (
    #|i=0
    #|while IFS= read -r line; do
    #|  i=$((i + 1))
    #|  if [ "$i" = "1" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-03-26","capabilities":{},"serverInfo":{"name":"srv"}}}'
    #|  elif [ "$i" = "3" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"call":1}}'
    #|  elif [ "$i" = "4" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":3,"result":{"call":2}}'
    #|  fi
    #|done
  )
}
