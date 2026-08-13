///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx daemon: reuses keep-alive stdio client" {
  let home = "/tmp/mcpx-daemon-reuse-test/home"
  @fs.remove_file(mcpx_daemon_state_path(home~)) catch {
    _ => ()
  }
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => run_mcpx_daemon_foreground(home~))
    let port = wait_for_daemon_port(home)
    inspect(port > 0, content="true")
    let server = @config.mcp_server_config(
      name="local",
      transport=Stdio,
      command=Some("/bin/sh"),
      args=["-c", daemon_reuse_script()],
      lifecycle=Some(@config.server_lifecycle(KeepAlive)),
    )
    let first = daemon_call_tool(
      home~,
      key="local",
      server~,
      tool_name="count",
      arguments=Json::empty_object(),
    )
    let second = daemon_call_tool(
      home~,
      key="local",
      server~,
      tool_name="count",
      arguments=Json::empty_object(),
    )
    inspect(
      first.stringify() + "|" + second.stringify(),
      content="{\"call\":1}|{\"call\":2}",
    )
    ignore(daemon_stop(home~))
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx daemon: idle timeout evicts stale stdio client" {
  let home = "/tmp/mcpx-daemon-idle-test/home"
  @fs.remove_file(mcpx_daemon_state_path(home~)) catch {
    _ => ()
  }
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => run_mcpx_daemon_foreground(home~))
    let port = wait_for_daemon_port(home)
    inspect(port > 0, content="true")
    let server = @config.mcp_server_config(
      name="local",
      transport=Stdio,
      command=Some("/bin/sh"),
      args=["-c", daemon_reuse_script()],
      lifecycle=Some(
        @config.server_lifecycle(KeepAlive, idle_timeout_ms=Some(50)),
      ),
    )
    let first = daemon_call_tool(
      home~,
      key="local",
      server~,
      tool_name="count",
      arguments=Json::empty_object(),
    )
    @async.sleep(90)
    let second = daemon_call_tool(
      home~,
      key="local",
      server~,
      tool_name="count",
      arguments=Json::empty_object(),
    )
    inspect(
      first.stringify() + "|" + second.stringify(),
      content="{\"call\":1}|{\"call\":1}",
    )
    ignore(daemon_stop(home~))
  })
}

///|
async test "mcpx daemon: stop exits foreground and removes state" {
  let home = "/tmp/mcpx-daemon-stop-exit-test/home"
  @fs.remove_file(mcpx_daemon_state_path(home~)) catch {
    _ => ()
  }
  @async.with_task_group(group => {
    let daemon_task = group.spawn(no_wait=true, () => {
      run_mcpx_daemon_foreground(home~)
    })
    let port = wait_for_daemon_port(home)
    inspect(port > 0, content="true")
    inspect(daemon_stop(home~), content="true")
    let exited = wait_for_daemon_task_exit(daemon_task, timeout_ms=500)
    if !exited {
      daemon_task.cancel()
    }
    inspect(exited, content="true")
    inspect(daemon_state_absent(home), content="true")
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx daemon: stop closes keep-alive stdio pool" {
  let home = "/tmp/mcpx-daemon-stop-pool-test/home"
  let marker = "/tmp/mcpx-daemon-stop-pool-test.marker"
  @fs.remove_file(mcpx_daemon_state_path(home~)) catch {
    _ => ()
  }
  @fs.remove_file(marker) catch {
    _ => ()
  }
  @async.with_task_group(group => {
    let daemon_task = group.spawn(no_wait=true, () => {
      run_mcpx_daemon_foreground(home~)
    })
    let port = wait_for_daemon_port(home)
    inspect(port > 0, content="true")
    let server = @config.mcp_server_config(
      name="local",
      transport=Stdio,
      command=Some("/bin/sh"),
      args=["-c", daemon_shutdown_marker_script(marker)],
      lifecycle=Some(@config.server_lifecycle(KeepAlive)),
    )
    let result = daemon_call_tool(
      home~,
      key="local",
      server~,
      tool_name="count",
      arguments=Json::empty_object(),
    )
    inspect(result.stringify(), content="{\"call\":1}")
    inspect(daemon_stop(home~), content="true")
    let exited = wait_for_daemon_task_exit(daemon_task, timeout_ms=500)
    let marker_written = wait_for_file(marker, timeout_ms=700)
    if !exited {
      daemon_task.cancel()
    }
    inspect(exited, content="true")
    inspect(marker_written, content="true")
    if marker_written {
      let content = @fs.read_file_to_string(marker) catch { _ => "" }
      inspect(content.length() > 0, content="true")
    }
    inspect(daemon_state_absent(home), content="true")
  })
  @fs.remove_file(marker) catch {
    _ => ()
  }
}

///|
async fn wait_for_daemon_port(home : String) -> Int {
  for i in 0..<100 {
    ignore(i)
    match read_mcpx_daemon_port(home~) {
      Some(port) => break port
      None => @async.sleep(20)
    }
  } nobreak {
    0
  }
}

///|
async fn wait_for_daemon_task_exit(
  task : @async.Task[Unit],
  timeout_ms~ : Int,
) -> Bool {
  @async.with_timeout_opt(timeout_ms, () => task.wait()) is Some(_)
}

///|
fn daemon_state_absent(home : String) -> Bool {
  read_mcpx_daemon_port(home~) is None
}

///|
async fn wait_for_file(path : String, timeout_ms~ : Int) -> Bool {
  let mut elapsed = 0
  while elapsed < timeout_ms {
    if @fs.path_exists(path) {
      return true
    }
    @async.sleep(20)
    elapsed = elapsed + 20
  }
  @fs.path_exists(path)
}

///|
async test "mcpx daemon: stop while concurrent call_tool is in-flight" {
  let home = "/tmp/mcpx-daemon-stop-concurrent-test/home"
  @fs.remove_file(mcpx_daemon_state_path(home~)) catch {
    _ => ()
  }
  @async.with_task_group(group => {
    let daemon_task = group.spawn(no_wait=true, () => {
      run_mcpx_daemon_foreground(home~)
    })
    let port = wait_for_daemon_port(home)
    inspect(port > 0, content="true")
    let server = @config.mcp_server_config(
      name="local",
      transport=Stdio,
      command=Some("/bin/sh"),
      args=["-c", daemon_reuse_script()],
      lifecycle=Some(@config.server_lifecycle(KeepAlive)),
    )
    let first = daemon_call_tool(
      home~,
      key="local",
      server~,
      tool_name="count",
      arguments=Json::empty_object(),
    )
    inspect(first.stringify(), content="{\"call\":1}")
    inspect(daemon_stop(home~), content="true")
    let call_after : Result[Json, _] = try
      daemon_call_tool(
        home~,
        key="local",
        server~,
        tool_name="count",
        arguments=Json::empty_object(),
      )
      |> Ok
    catch {
      e => Err(e)
    }
    match call_after {
      Err(_) => inspect(true, content="true")
      Ok(_) => inspect(false, content="true")
    }
    let exited = wait_for_daemon_task_exit(daemon_task, timeout_ms=500)
    if !exited {
      daemon_task.cancel()
    }
    inspect(exited, content="true")
    inspect(daemon_state_absent(home), content="true")
  })
}

///|
async test "mcpx daemon: stop when not running returns false" {
  let home = "/tmp/mcpx-daemon-stop-not-running-test/home"
  @fs.remove_file(mcpx_daemon_state_path(home~)) catch {
    _ => ()
  }
  let result : Result[Bool, _] = try daemon_stop(home~) |> Ok catch {
    e => Err(e)
  }
  match result {
    Err(_) => inspect(true, content="true")
    Ok(_) => inspect(false, content="true")
  }
}

///|
async test "mcpx daemon: double stop" {
  let home = "/tmp/mcpx-daemon-double-stop-test/home"
  @fs.remove_file(mcpx_daemon_state_path(home~)) catch {
    _ => ()
  }
  @async.with_task_group(group => {
    let daemon_task = group.spawn(no_wait=true, () => {
      run_mcpx_daemon_foreground(home~)
    })
    let port = wait_for_daemon_port(home)
    inspect(port > 0, content="true")
    inspect(daemon_stop(home~), content="true")
    let exited = wait_for_daemon_task_exit(daemon_task, timeout_ms=500)
    if !exited {
      daemon_task.cancel()
    }
    inspect(exited, content="true")
    let second_stop : Result[Bool, _] = try daemon_stop(home~) |> Ok catch {
      e => Err(e)
    }
    match second_stop {
      Err(_) => inspect(true, content="true")
      Ok(_) => inspect(false, content="true")
    }
    inspect(daemon_state_absent(home), content="true")
  })
}

///|
async test "mcpx daemon: restart after stop" {
  let home = "/tmp/mcpx-daemon-restart-test/home"
  @fs.remove_file(mcpx_daemon_state_path(home~)) catch {
    _ => ()
  }
  @async.with_task_group(group => {
    let daemon_task = group.spawn(no_wait=true, () => {
      run_mcpx_daemon_foreground(home~)
    })
    let port1 = wait_for_daemon_port(home)
    inspect(port1 > 0, content="true")
    inspect(daemon_stop(home~), content="true")
    let exited = wait_for_daemon_task_exit(daemon_task, timeout_ms=500)
    if !exited {
      daemon_task.cancel()
    }
    inspect(exited, content="true")
    inspect(daemon_state_absent(home), content="true")
    let daemon_task2 = group.spawn(no_wait=true, () => {
      run_mcpx_daemon_foreground(home~)
    })
    let port2 = wait_for_daemon_port(home)
    inspect(port2 > 0, content="true")
    inspect(daemon_ping(home~), content="true")
    inspect(daemon_stop(home~), content="true")
    let exited2 = wait_for_daemon_task_exit(daemon_task2, timeout_ms=500)
    if !exited2 {
      daemon_task2.cancel()
    }
    inspect(exited2, content="true")
  })
}

///|
fn daemon_reuse_script() -> String {
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

///|
fn daemon_shutdown_marker_script(marker : String) -> String {
  (
    #|marker='
  ) +
  marker +
  (
    #|'
    #|trap 'printf signal > "$marker"; exit 0' TERM INT
    #|i=0
    #|while IFS= read -r line; do
    #|  i=$((i + 1))
    #|  if [ "$i" = "1" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-03-26","capabilities":{},"serverInfo":{"name":"srv"}}}'
    #|  elif [ "$i" = "3" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"call":1}}'
    #|  fi
    #|done
    #|printf eof > "$marker"
  )
}
