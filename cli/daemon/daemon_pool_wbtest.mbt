///|
#cfg(all(target="native", not(platform="windows")))
async test "mcpx daemon: pool lookups share mutable last-used state" {
  @async.with_task_group(group => {
    let pool = daemon_pool()
    defer pool.close_all()
    let server = @config.mcp_server_config(
      name="local",
      transport=Stdio,
      command=Some("/bin/sh"),
      args=["-c", daemon_reuse_script()],
      lifecycle=Some(
        @config.server_lifecycle(KeepAlive, idle_timeout_ms=Some(60000)),
      ),
    )
    let first = pool.entry(group, "shared", server)
    let second = pool.entry(group, "shared", server)
    first.last_used_ms = 0
    inspect(second.last_used_ms, content="0")
    inspect(pool.entries["shared"].last_used_ms, content="0")
    inspect(second.is_idle_expired(), content="true")
    second.mark_used()
    assert_true(first.last_used_ms > 0)
    assert_eq(first.last_used_ms, pool.entries["shared"].last_used_ms)
    inspect(first.is_idle_expired(), content="false")
    let first_result = first.client.call_tool(tool_name="count", arguments={})
    let second_result = second.client.call_tool(tool_name="count", arguments={})
    json_inspect(first_result, content={ "call": 1 })
    json_inspect(second_result, content={ "call": 2 })
    inspect(pool.entries.length(), content="1")
  })
}
