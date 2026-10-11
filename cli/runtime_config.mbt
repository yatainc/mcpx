///|
priv struct ServerBinding {
  source_file : String
  cwd_base : String
  server : @config.McpServerConfig
}

///|
priv suberror RuntimeConfigError {
  RuntimeConfigError(String)
}

///|
impl Show for RuntimeConfigError with fn output(self, logger) {
  let RuntimeConfigError(message) = self
  logger.write_string(message)
}

///|
fn ServerBinding::identity(self : ServerBinding) -> String {
  let text = [self.source_file, self.server.name].to_json().stringify()
  "config:sha256:" +
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(text)))
}

///|
// Do not normalize lexically: symlink/.. must be resolved by the filesystem.
fn absolute_path(base : String, path : String) -> String {
  if @path.Path(path).is_absolute() {
    return path
  }
  let sep = @path.sep.to_string()
  base + (if base.has_suffix(sep) { "" } else { sep }) + path
}

///|
async fn git_root(cwd : String) -> String? {
  let env = @env.get_env_vars()
  for key in env.keys().to_array() {
    if key.has_prefix("GIT_") {
      env.remove(key)
    }
  }
  env["LC_ALL"] = "C"
  let (code, out, err) = @async.with_timeout(3000, () => {
    @process.collect_output(
      "git",
      ["-C", cwd, "rev-parse", "--show-toplevel"],
      extra_env=env,
      inherit_env=false,
    )
  }) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => return None
    @async.TimeoutError =>
      raise RuntimeConfigError("Git root discovery timed out")
    error => raise error
  }
  if code != 0 {
    let message = err.text()
    if message.has_prefix("fatal: not a git repository (or any") ||
      message == "fatal: this operation must be run in a work tree\n" {
      return None
    }
    raise RuntimeConfigError("failed to discover Git root: " + message)
  }
  guard out.text().strip_suffix("\n") is Some(root) &&
    @path.Path(root.to_owned()).is_absolute() else {
    raise RuntimeConfigError("invalid Git root response")
  }
  Some(root.to_owned())
}

///|
async fn load_config_root(
  root : String,
  into : Map[String, ServerBinding],
  cwd_base? : String,
) -> Unit {
  let root = @async_fs.realpath(root) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => return
    error => raise error
  }
  for filename in ["mcp.jsonc", "mcp.json", ".mcp.jsonc", ".mcp.json"] {
    let file = absolute_path(root, filename)
    let kind = @async_fs.kind(file, follow_symlink=false) catch {
      @os_error.OSError(_) as error if error.is_ENOENT() => continue
      error => raise error
    }
    // An existing dangling symlink or non-file is an error, not absence.
    let config = try {
      if !(kind is Regular) && !(@async_fs.kind(file) is Regular) {
        raise RuntimeConfigError("config is not a regular file")
      }
      let text = @async_fs.read_file(file).text()
      @config.decode_mcpx_config(@json.parse(@config.normalize_jsonc(text)))
    } catch {
      error =>
        raise RuntimeConfigError(
          "failed to load config: " + file + ": " + error.to_string(),
        )
    }
    for name, server in config.servers {
      into[name] = {
        source_file: file,
        cwd_base: cwd_base.unwrap_or(root),
        server,
      }
    }
    return
  }
}

///|
async fn load_servers(
  paths : @app_paths.McpxAppPaths,
  cwd : String,
) -> Map[String, ServerBinding] {
  let cwd = @async_fs.realpath(cwd)
  let servers = Map([])
  load_config_root(absolute_path(cwd, paths.config_dir), servers, cwd_base=cwd)
  if git_root(cwd) is Some(root) {
    load_config_root(root, servers)
  }
  servers
}

///|
// Resolve PATH here: posix_spawnp may search the daemon's PATH, not child env.
async fn resolve_executable(
  command : String,
  cwd : String,
  env : Map[String, String],
) -> String {
  if @path.Path(command).is_absolute() ||
    command.contains(@path.sep.to_string()) {
    return absolute_path(cwd, command)
  }
  guard env.get("PATH") is Some(path) else {
    raise RuntimeConfigError(
      "PATH is not set; use an executable path: " + command,
    )
  }
  for directory in path.split(@path.delimiter.to_string()) {
    let candidate = absolute_path(
      absolute_path(cwd, directory.to_owned()),
      command,
    )
    let executable = @async_fs.can_execute(candidate) catch {
      @os_error.OSError(_) as error if error.is_ENOTDIR() => false
      error => raise error
    }
    if executable && @async_fs.kind(candidate) is Regular {
      return candidate
    }
  }
  raise RuntimeConfigError("executable not found: " + command)
}

///|
async fn prepare_server(
  binding : ServerBinding,
  env_file : String,
) -> @config.McpServerConfig {
  let server = match resolve_runtime_server(binding.server, env_file) {
    Ok(server) => server
    Err(message) => raise RuntimeConfigError(message)
  }
  if server.transport is Http {
    return server
  }
  let cwd = @async_fs.realpath(
    absolute_path(binding.cwd_base, server.cwd.unwrap_or(".")),
  )
  let env = @config.merge_env(@env.get_env_vars(), server.env)
  let command = resolve_executable(server.command.unwrap(), cwd, env)
  @config.mcp_server_config(
    name=server.name,
    transport=Stdio,
    command=Some(command),
    args=server.args,
    env~,
    cwd=Some(cwd),
    headers=server.headers,
    auth=server.auth,
    protocol_mode=server.protocol_mode,
    lifecycle=server.lifecycle,
    allowed_tools=server.allowed_tools,
    disabled_tools=server.disabled_tools,
    description=server.description,
  )
}
