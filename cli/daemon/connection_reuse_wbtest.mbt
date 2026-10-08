///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx daemon: list and call derive the same connection identity" {
  let home = "/tmp/mcpx-daemon-list-call-identity-test/home"
  @fs.remove_file(mcpx_daemon_state_path(home~)) catch {
    _ => ()
  }
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => run_mcpx_daemon_foreground(home~))
    inspect(wait_for_daemon_port(home) > 0, content="true")
    let server = @config.mcp_server_config(
      name="local",
      transport=Stdio,
      command=Some("/bin/sh"),
      args=[
        "-c",
        (
          #|i=0
          #|while IFS= read -r line; do
          #|  i=$((i + 1))
          #|  if [ "$i" = "1" ]; then
          #|    printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","capabilities":{}}}'
          #|  elif [ "$i" = "3" ]; then
          #|    printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"count","inputSchema":{}}]}}'
          #|  elif [ "$i" = "4" ]; then
          #|    printf '%s\n' '{"jsonrpc":"2.0","id":3,"result":{"reused":true}}'
          #|  fi
          #|done
        ),
      ],
      lifecycle=Some(@config.server_lifecycle(KeepAlive)),
    )
    let tools = daemon_list_tools(home~, server_name="local", server~)
    inspect(tools[0].name, content="count")
    let result = daemon_call_tool(
      home~,
      server_name="local",
      server~,
      tool_name="count",
      arguments={},
    )
    json_inspect(result, content={ "reused": true })
    ignore(daemon_stop(home~))
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx daemon: concurrent calls serialize on one reused client" {
  let home = "/tmp/mcpx-daemon-concurrent-reuse-test/home"
  @fs.remove_file(mcpx_daemon_state_path(home~)) catch {
    _ => ()
  }
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => run_mcpx_daemon_foreground(home~))
    assert_true(wait_for_daemon_port(home) > 0)
    let server = @config.mcp_server_config(
      name="local",
      transport=Stdio,
      command=Some("/bin/sh"),
      args=["-c", daemon_reuse_script()],
      lifecycle=Some(@config.server_lifecycle(KeepAlive)),
    )
    let call : async () -> String = () => {
      let result = daemon_call_tool(
        home~,
        server_name="local",
        server~,
        tool_name="count",
        arguments={},
      )
      result.stringify()
    }
    let first = group.spawn(no_wait=true, call)
    let second = group.spawn(no_wait=true, call)
    let first_result = first.wait()
    let second_result = second.wait()
    assert_true(
      (first_result == "{\"call\":1}" && second_result == "{\"call\":2}") ||
      (first_result == "{\"call\":2}" && second_result == "{\"call\":1}"),
    )
    ignore(daemon_stop(home~))
  })
}
