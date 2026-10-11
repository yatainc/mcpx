///|
fn identity_fixture(
  env? : Map[String, String] = { "TOKEN": "secret-a", "PATH": "/bin" },
  command? : String = "/bin/sh",
  args? : Array[String] = ["arg-secret"],
  cwd? : String = "/project/a",
  mode? : @config.McpConnectionMode = Stateful,
  timeout? : Int = 300000,
) -> @config.McpServerConfig {
  @config.mcp_server_config(
    name="local",
    transport=Stdio,
    command=Some(command),
    args~,
    env~,
    cwd=Some(cwd),
    protocol_mode=Some(mode),
    lifecycle=Some(
      @config.server_lifecycle(KeepAlive, idle_timeout_ms=Some(timeout)),
    ),
  )
}

///|
test "daemon key contains no launch secrets and ignores map insertion order" {
  let key = daemon_pool_key("scope-a", identity_fixture())
  assert_eq(key.length(), 64)
  for secret in ["TOKEN", "secret-a", "arg-secret", "/project/a", "scope-a"] {
    assert_false(key.contains(secret))
  }
  assert_eq(
    key,
    daemon_pool_key(
      "scope-a",
      identity_fixture(env={ "PATH": "/bin", "TOKEN": "secret-a" }),
    ),
  )
}

///|
test "daemon key separates scope and every effective launch condition" {
  let base = daemon_pool_key("scope-a", identity_fixture())
  assert_true(base != daemon_pool_key("scope-b", identity_fixture()))
  for
    server in [
      identity_fixture(env={ "TOKEN": "secret-b", "PATH": "/bin" }),
      identity_fixture(env={ "PATH": "/bin" }),
      identity_fixture(command="/other/sh"),
      identity_fixture(args=["different"]),
      identity_fixture(cwd="/project/b"),
      identity_fixture(mode=Stateless),
      identity_fixture(mode=Auto),
      identity_fixture(timeout=1),
    ] {
    assert_true(base != daemon_pool_key("scope-a", server))
  }
}
