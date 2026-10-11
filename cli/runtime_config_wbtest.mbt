///|
async test "config roots use the same four filenames and stop at the first existing file" {
  let root = @async_fs.tmpdir(prefix="mcpx-config-")
  defer @async_fs.rmdir(root, recursive=true)
  let root = @async_fs.realpath(root)
  let names = ["mcp.jsonc", "mcp.json", ".mcp.jsonc", ".mcp.json"]
  for project in [false, true] {
    let cwd_base = if project { None } else { Some(root + "/caller") }
    for filename in names {
      @async_fs.write_file(
        root + "/" + filename,
        "{\"mcpServers\":{\"local\":{\"command\":\"node\",},},}// comment",
      )
    }
    for filename in names {
      let servers = Map([])
      load_config_root(root, servers, cwd_base?)
      let selected = servers["local"]
      assert_eq(selected.source_file, root + "/" + filename)
      assert_eq(selected.cwd_base, cwd_base.unwrap_or(root))
      assert_true(selected.server.transport is Stdio)
      @async_fs.remove(root + "/" + filename)
    }
    let empty = Map([])
    load_config_root(root, empty, cwd_base?)
    assert_true(empty.is_empty())
  }
  @async_fs.write_file(root + "/mcp.jsonc", "{\"mcpServers\":{}}")
  @async_fs.write_file(root + "/mcp.json", "invalid lower-priority file")
  load_config_root(root, Map([]))
  @async_fs.write_file(root + "/mcp.jsonc", "invalid selected file")
  try load_config_root(root, Map([])) catch {
    RuntimeConfigError(message) => assert_true(message.contains("mcp.jsonc"))
    error => fail("wrong config error: \{error}")
  } noraise {
    _ => fail("invalid selected config was ignored")
  }
  @async_fs.write_file(
    root + "/mcp.jsonc",
    "{\"mcpServers\":{\"bad\":{\"transport\":\"sse\",\"url\":\"https://example.test\"}}}",
  )
  try load_config_root(root, Map([])) catch {
    RuntimeConfigError(message) => {
      assert_true(message.contains("mcp.jsonc"))
      assert_true(message.contains("unsupported transport: sse"))
    }
    error => fail("wrong config error: \{error}")
  } noraise {
    _ => fail("invalid selected transport was ignored")
  }
}

///|
async test "project overrides the entire server and retains source identity" {
  let root = @async_fs.tmpdir(prefix="mcpx-merge-")
  defer @async_fs.rmdir(root, recursive=true)
  let user = root + "/user"
  let project = root + "/project"
  @async_fs.mkdir(user)
  @async_fs.mkdir(project)
  @async_fs.write_file(
    user + "/.mcp.json",
    (
      #|{"mcpServers":{"same":{"url":"https://example.test","env":{"TOKEN":"user"},"headers":{"Authorization":"user"},"auth":{"type":"oauth"},"disabledTools":["run"]},"other":{"command":"unused"}}}
    ),
  )
  @async_fs.write_file(
    project + "/.mcp.json",
    "{\"mcpServers\":{\"same\":{\"command\":\"node\"}}}",
  )
  let servers = Map([])
  load_config_root(user, servers, cwd_base=root)
  let user_identity = servers["same"].identity()
  load_config_root(project, servers)
  let selected = servers["same"]
  assert_true(selected.identity() != user_identity)
  assert_true(selected.identity() != servers["other"].identity())
  assert_eq(servers.length(), 2)
  assert_true(selected.server.url is None)
  assert_true(selected.server.auth is None)
  assert_true(selected.server.headers.is_empty())
  assert_true(selected.server.env.is_empty())
  assert_true(selected.server.disabled_tools.is_empty())
}

///|
async test "selected dangling symlinks and directories never activate a fallback" {
  let root = @async_fs.tmpdir(prefix="mcpx-config-kind-")
  defer @async_fs.rmdir(root, recursive=true)
  @async_fs.write_file(root + "/mcp.json", "{\"mcpServers\":{}}")
  for directory in [false, true] {
    let selected = root + "/mcp.jsonc"
    if directory {
      @async_fs.mkdir(selected)
    } else {
      @async_fs.symlink(target=root + "/missing", selected)
    }
    try load_config_root(root, Map([])) catch {
      RuntimeConfigError(message) => assert_true(message.contains(selected))
      error => fail("wrong config error: \{error}")
    } noraise {
      _ => fail("invalid selected source treated as absent")
    }
    if directory {
      @async_fs.rmdir(selected)
    } else {
      @async_fs.remove(selected)
    }
  }
}

///|
async test "projects sharing a config symlink still have different origins and working directories" {
  let root = @async_fs.tmpdir(prefix="mcpx-config-symlink-")
  defer @async_fs.rmdir(root, recursive=true)
  let root = @async_fs.realpath(root)
  @async_fs.write_file(
    root + "/shared.json",
    "{\"mcpServers\":{\"same\":{\"command\":\"/bin/sh\"}}}",
  )
  let ids = []
  for name in ["a", "b"] {
    let directory = root + "/" + name
    @async_fs.mkdir(directory)
    @async_fs.symlink(target=root + "/shared.json", directory + "/.mcp.json")
    let servers = Map([])
    load_config_root(directory, servers)
    ids.push(servers["same"].identity())
    let prepared = prepare_server(servers["same"], root + "/missing.env")
    assert_eq(prepared.cwd, Some(directory))
  }
  assert_true(ids[0] != ids[1])
}

///|
async test "path resolution preserves filesystem meaning of symlinks before parent components" {
  let root = @async_fs.tmpdir(prefix="mcpx-symlink-parent-")
  defer @async_fs.rmdir(root, recursive=true)
  let root = @async_fs.realpath(root)
  let project = root + "/project"
  let target = root + "/target"
  for directory in [project + "/bin", target + "/bin", target + "/deep"] {
    @async_fs.mkdir(directory, recursive=true)
  }
  @async_fs.symlink(target=target + "/deep", project + "/link")
  for directory in [project, target] {
    @async_fs.write_file(directory + "/bin/peer", "#!/bin/sh\nexit 0\n")
    @async_fs.chmod(directory + "/bin/peer", 493)
  }
  for command in ["peer", "link/../bin/peer", project + "/link/../bin/peer"] {
    let executable = resolve_executable(command, project, {
      "PATH": "link/../bin",
    })
    assert_eq(@async_fs.realpath(executable), target + "/bin/peer")
  }
  let binding : ServerBinding = {
    source_file: project + "/.mcp.json",
    cwd_base: project,
    server: @config.mcp_server_config(
      name="peer",
      transport=Stdio,
      command=Some(target + "/bin/peer"),
      cwd=Some("link/.."),
    ),
  }
  assert_eq(prepare_server(binding, root + "/missing.env").cwd, Some(target))
  for directory in [project, target] {
    @async_fs.mkdir(directory + "/config/mcpx", recursive=true)
    let config : Json = {
      "mcpServers": { "selected": { "command": directory + "/bin/peer" } },
    }
    @async_fs.write_file(
      directory + "/config/mcpx/mcp.json",
      config.stringify(),
    )
  }
  let paths = @app_paths.mcpx_app_paths(
    root,
    config_home=Some(project + "/link/../config"),
  )
  let servers = load_servers(paths, root)
  assert_eq(servers["selected"].source_file, target + "/config/mcpx/mcp.json")
  assert_eq(servers["selected"].server.command, Some(target + "/bin/peer"))
}

///|
async test "missing cwd components before parent components are not silently erased" {
  let root = @async_fs.tmpdir(prefix="mcpx-missing-cwd-")
  defer @async_fs.rmdir(root, recursive=true)
  let binding : ServerBinding = {
    source_file: root + "/.mcp.json",
    cwd_base: root,
    server: @config.mcp_server_config(
      name="peer",
      transport=Stdio,
      command=Some("/bin/sh"),
      cwd=Some("missing/.."),
    ),
  }
  try prepare_server(binding, root + "/missing.env") catch {
    @os_error.OSError(_) as error => assert_true(error.is_ENOENT())
    error => fail("wrong cwd error: \{error}")
  } noraise {
    _ => fail("nonexistent cwd was normalized into an existing directory")
  }
}

///|
async test "prepare binds project cwd PATH and explicit env without exporting the user dotenv" {
  let root = @async_fs.tmpdir(prefix="mcpx-prepare-")
  defer @async_fs.rmdir(root, recursive=true)
  let root = @async_fs.realpath(root)
  @async_fs.mkdir(root + "/bin")
  @async_fs.mkdir(root + "/work")
  @async_fs.write_file(root + "/bin/peer", "#!/bin/sh\nexit 0\n")
  @async_fs.chmod(root + "/bin/peer", 493)
  @async_fs.write_file(
    root + "/.env",
    "MCPX_TEST_CONFIG_VALUE=expanded\nMCPX_TEST_CONFIG_CWD=work\nMCPX_DOTENV_NOT_EXPORTED=private\n",
  )
  let binding : ServerBinding = {
    source_file: root + "/.mcp.json",
    cwd_base: root,
    server: @config.mcp_server_config(
      name="peer",
      transport=Stdio,
      command=Some("peer"),
      cwd=Some("${MCPX_TEST_CONFIG_CWD}"),
      args=["./relative-script"],
      env={ "PATH": "../bin", "VALUE": "${MCPX_TEST_CONFIG_VALUE}" },
    ),
  }
  let prepared = prepare_server(binding, root + "/.env")
  assert_eq(@async_fs.realpath(prepared.command.unwrap()), root + "/bin/peer")
  assert_eq(prepared.cwd, Some(root + "/work"))
  assert_eq(prepared.args, ["./relative-script"])
  assert_eq(prepared.env["VALUE"], "expanded")
  assert_eq(
    prepared.env.get("MCPX_DOTENV_NOT_EXPORTED"),
    @env.get_env_vars().get("MCPX_DOTENV_NOT_EXPORTED"),
  )
  assert_eq(
    resolve_executable("peer", root + "/bin", { "PATH": ":/missing" }),
    root + "/bin/peer",
  )
  assert_eq(
    @async_fs.realpath(resolve_executable("./bin/peer", root, Map([]))),
    root + "/bin/peer",
  )
  // PATH entries can be stale files rather than directories; skip them.
  assert_eq(
    resolve_executable("peer", root, { "PATH": "bin/peer:/missing:bin" }),
    root + "/bin/peer",
  )
}
