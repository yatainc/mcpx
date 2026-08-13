///|
pub suberror McpxDaemonError {
  Unavailable
  ConnectFailed(String)
  InvalidResponse(String)
  RemoteError(String)
  Stdio(String)
} derive(Debug)

///|
pub fn describe_mcpx_daemon_error(error : McpxDaemonError) -> String {
  match error {
    Unavailable => "daemon unavailable"
    ConnectFailed(message) => "connect failed: " + message
    InvalidResponse(message) => "invalid response: " + message
    RemoteError(message) => "remote error: " + message
    Stdio(message) => "stdio error: " + message
  }
}

///|
priv suberror McpxDaemonStop

///|
priv struct DaemonEntry {
  client : @mcp_stdio.StdioMcpClient
  mutex : @async.Semaphore
  idle_timeout_ms : Int?
  mut last_used_ms : Int64
}

///|
priv struct DaemonPool {
  entries : Map[String, Ref[DaemonEntry]]
  lock : @async.Semaphore
}

///|
fn daemon_pool() -> DaemonPool {
  { entries: Map([]), lock: Semaphore(1) }
}

///|
pub fn mcpx_daemon_state_path(
  home~ : String,
  config_home? : String? = None,
) -> String {
  @app_paths.mcpx_app_paths(home, config_home~).config_dir + "/daemon.json"
}

///|
pub fn read_mcpx_daemon_port(
  home~ : String,
  config_home? : String? = None,
) -> Int? {
  let path = mcpx_daemon_state_path(home~, config_home~)
  if !@fs.path_exists(path) {
    return None
  }
  let text = @fs.read_file_to_string(path) catch { _ => return None }
  let json = @json.parse(text) catch { _ => return None }
  match json {
    Object(obj) =>
      match obj.get("port") {
        Some(Number(value, ..)) if value.trunc() == value =>
          Some(value.to_int())
        _ => None
      }
    _ => None
  }
}

///|
pub async fn run_mcpx_daemon_foreground(
  home~ : String,
  config_home? : String? = None,
) -> Unit {
  @async.with_task_group(group => {
    let pool = daemon_pool()
    let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
    let port = server.addr.port()
    write_daemon_state(home~, config_home~, port~)
    defer pool.close_all()
    group.add_defer(() => remove_daemon_state(home~, config_home~))
    server.run_forever(allow_failure=false, (conn, _) => {
      handle_conn(conn, group, pool)
    }) catch {
      McpxDaemonStop => ()
      err => raise err
    }
  }) catch {
    _ => ()
  }
}

///|
pub async fn daemon_ping(home~ : String, config_home? : String? = None) -> Bool {
  let req = Json::object({ "op": Json::string("ping") })
  let result : Result[Json, _] = try
    request(home~, config_home~, req) |> Ok
  catch {
    e => Err(e)
  }
  match result {
    Ok(Object(obj)) => obj.get("ok") == Some(Json::boolean(true))
    _ => false
  }
}

///|
pub async fn ensure_mcpx_daemon_running(
  home~ : String,
  config_home? : String? = None,
) -> Bool raise McpxDaemonError {
  if (daemon_ping(home~, config_home~) catch { _ => false }) {
    return true
  }
  start_daemon_process()
  for _ in 0..<100 {
    if (daemon_ping(home~, config_home~) catch { _ => false }) {
      return true
    }
    @async.sleep(50) catch {
      _ => raise Unavailable
    }
  }
  raise Unavailable
}

///|
async fn start_daemon_process() -> Unit raise McpxDaemonError {
  let exe = @env.args().get(0).unwrap_or("mcpx")
  let (stdin, stdin_writer) = @process.write_to_process() catch {
    error => raise ConnectFailed(error.to_string())
  }
  defer stdin_writer.close()
  let (stdout_reader, stdout) = @process.read_from_process() catch {
    error => raise ConnectFailed(error.to_string())
  }
  defer stdout_reader.close()
  let (stderr_reader, stderr) = @process.read_from_process() catch {
    error => raise ConnectFailed(error.to_string())
  }
  defer stderr_reader.close()
  ignore(
    @process.spawn_orphan(
      exe,
      [],
      extra_env={ "MCPX_INTERNAL_DAEMON": "serve" },
      stdin~,
      stdout~,
      stderr~,
    ) catch {
      error => raise ConnectFailed(error.to_string())
    },
  )
}

///|
pub async fn daemon_call_tool(
  home~ : String,
  config_home? : String? = None,
  key~ : String,
  server~ : @config.McpServerConfig,
  tool_name~ : String,
  arguments~ : Json,
) -> Json raise McpxDaemonError {
  ignore(ensure_mcpx_daemon_running(home~, config_home~))
  let req = Json::object({
    "op": Json::string("call_tool"),
    "key": Json::string(key),
    "server": server.to_json(),
    "tool": Json::string(tool_name),
    "args": arguments,
  })
  let response = request(home~, config_home~, req)
  decode_result(response)
}

///|
pub async fn daemon_list_tools(
  home~ : String,
  config_home? : String? = None,
  key~ : String,
  server~ : @config.McpServerConfig,
) -> Array[@mcp_client.McpToolInfo] raise McpxDaemonError {
  ignore(ensure_mcpx_daemon_running(home~, config_home~))
  let req = Json::object({
    "op": Json::string("list_tools"),
    "key": Json::string(key),
    "server": server.to_json(),
  })
  let response = request(home~, config_home~, req)
  decode_tools(response)
}

///|
pub async fn daemon_stop(
  home~ : String,
  config_home? : String? = None,
) -> Bool raise McpxDaemonError {
  let req = Json::object({ "op": Json::string("stop") })
  let response = request(home~, config_home~, req)
  match response {
    Object(obj) =>
      if obj.get("ok") == Some(Json::boolean(true)) {
        wait_for_daemon_state_removed(home~, config_home~) catch {
          _ => false
        }
      } else {
        false
      }
    _ => false
  }
}
