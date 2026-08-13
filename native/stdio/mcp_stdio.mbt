///|
pub suberror McpStdioError {
  SpawnFailed(String)
  ReadFailed(String)
  WriteFailed(String)
  InvalidJson(String)
  Protocol(String)
  UnexpectedEof
} derive(Debug)

///|
priv struct StdioConnection {
  reader : @process.ReadFromProcess
  _stdout_handle : &@process.ProcessOutput
  _stderr_handle : &@process.ProcessOutput
  writer : @process.WriteToProcess
  _stdin_handle : &@process.ProcessInput
  process : @process.Process
  mut closed : Bool
}

///|
pub(all) enum StdioProtocolLifecycle {
  Initialize
  Stateless
}

///|
pub struct StdioMcpClient {
  priv conn : StdioConnection
  client : @mcp_client.McpClient
  lifecycle : StdioProtocolLifecycle
  next_request_id : Ref[Int]
}

///|
pub async fn[X] stdio_mcp_connect(
  group : @async.TaskGroup[X],
  command~ : String,
  args~ : Array[String],
  env~ : Map[String, String],
  cwd~ : String?,
  mode? : @config.McpConnectionMode = @config.McpConnectionMode::Stateful,
) -> StdioMcpClient raise McpStdioError {
  let conn = spawn_stdio(group, command, args, env, cwd)
  let client = @mcp_client.mcp_client(
    client_name="mcpx",
    client_version="0.1.4",
    protocol_version=@mcp_client.MCP_PROTOCOL_VERSION_LEGACY,
  )
  let lifecycle = negotiate_stdio(conn, client, mode)
  { conn, client, lifecycle, next_request_id: Ref(2) }
}

///|
pub async fn StdioMcpClient::call_tool(
  self : StdioMcpClient,
  tool_name~ : String,
  arguments~ : Json,
) -> Json raise McpStdioError {
  match self.lifecycle {
    Initialize => {
      let request = self.client.tool_call_request(name=tool_name, arguments~)
      write_json_line(self.conn, request.message)
      let id = request.expected_id() catch {
        _ => raise McpStdioError::Protocol("mcp protocol error")
      }
      let response = read_response_for_id(self.conn, expected_id=id)
      self.client.accept_tool_call_response(request, response) catch {
        _ => raise McpStdioError::Protocol("mcp protocol error")
      }
    }
    Stateless => {
      let id = take_modern_request_id(self)
      write_json_line(
        self.conn,
        @mcp_client.mcp_tool_call_request(
          id~,
          name=tool_name,
          arguments~,
          client_name="mcpx",
          client_version="0.1.4",
        ),
      )
      let response = read_response_for_id(self.conn, expected_id=id)
      @mcp_client.decode_mcp_result(response, expected_id=id) catch {
        _ => raise McpStdioError::Protocol("mcp protocol error")
      }
    }
  }
}

///|
pub async fn StdioMcpClient::list_tools(
  self : StdioMcpClient,
) -> Array[@mcp_client.McpToolInfo] raise McpStdioError {
  match self.lifecycle {
    Initialize => {
      let request = self.client.tools_list_request()
      write_json_line(self.conn, request.message)
      let id = request.expected_id() catch {
        _ => raise McpStdioError::Protocol("mcp protocol error")
      }
      let response = read_response_for_id(self.conn, expected_id=id)
      self.client.accept_tools_list_response(request, response) catch {
        _ => raise McpStdioError::Protocol("mcp protocol error")
      }
    }
    Stateless => {
      let id = take_modern_request_id(self)
      write_json_line(
        self.conn,
        @mcp_client.mcp_tools_list_request(
          id~,
          client_name="mcpx",
          client_version="0.1.4",
        ),
      )
      let response = read_response_for_id(self.conn, expected_id=id)
      match
        @mcp_client.decode_mcp_tool_list_response(response, expected_id=id) {
        Ok(value) => value
        Err(_) => raise McpStdioError::Protocol("mcp protocol error")
      }
    }
  }
}

///|
pub fn StdioMcpClient::close(self : StdioMcpClient) -> Unit {
  close_stdio(self.conn)
}

///|
pub async fn stdio_mcp_call_tool(
  command~ : String,
  args~ : Array[String],
  env~ : Map[String, String],
  cwd~ : String?,
  tool_name~ : String,
  arguments~ : Json,
  mode? : @config.McpConnectionMode = @config.McpConnectionMode::Stateful,
) -> Json raise McpStdioError {
  @async.with_task_group(group => {
    let client = stdio_mcp_connect(group, command~, args~, env~, cwd~, mode~)
    defer client.close()
    client.call_tool(tool_name~, arguments~)
  }) catch {
    err => raise McpStdioError::Protocol(err.to_string())
  }
}

///|
pub async fn stdio_mcp_list_tools(
  command~ : String,
  args~ : Array[String],
  env~ : Map[String, String],
  cwd~ : String?,
  mode? : @config.McpConnectionMode = @config.McpConnectionMode::Stateful,
) -> Array[@mcp_client.McpToolInfo] raise McpStdioError {
  @async.with_task_group(group => {
    let client = stdio_mcp_connect(group, command~, args~, env~, cwd~, mode~)
    defer client.close()
    client.list_tools()
  }) catch {
    err => raise McpStdioError::Protocol(err.to_string())
  }
}

///|
async fn drain_process_stderr(reader : @process.ReadFromProcess) -> Unit {
  while true {
    let chunk = reader.read_some() catch { _ => None }
    match chunk {
      Some(_) => ()
      None => break
    }
  }
}

///|
fn take_modern_request_id(client : StdioMcpClient) -> Int {
  let id = client.next_request_id.val
  client.next_request_id.val = id + 1
  id
}

///|
async fn negotiate_stdio(
  conn : StdioConnection,
  client : @mcp_client.McpClient,
  mode : @config.McpConnectionMode,
) -> StdioProtocolLifecycle raise McpStdioError {
  if mode == @config.McpConnectionMode::Stateful {
    initialize_stdio(conn, client)
    return StdioProtocolLifecycle::Initialize
  }
  let context = @mcp_client.mcp_request_context(
    protocol=@mcp_client.McpProtocolVersion::V2026_07_28,
    client_name="mcpx",
    client_version="0.1.4",
  )
  write_json_line(conn, @mcp_client.mcp_discover_request(id=1, context))
  let response = read_response_for_id(conn, expected_id=1)
  match @mcp_client.decode_mcp_discover_response(response, expected_id=1) {
    Ok(discover) =>
      if discover.protocol_versions.contains(
          @mcp_client.McpProtocolVersion::V2026_07_28,
        ) {
        StdioProtocolLifecycle::Stateless
      } else {
        raise McpStdioError::Protocol("MCP 2026-07-28 is not supported")
      }
    Err(@mcp_client.McpProtocolError::RemoteError(-32601, _)) =>
      if mode == @config.McpConnectionMode::Auto {
        initialize_stdio(conn, client)
        StdioProtocolLifecycle::Initialize
      } else {
        raise McpStdioError::Protocol("stateless MCP is not supported")
      }
    Err(_) => raise McpStdioError::Protocol("MCP discovery failed")
  }
}

///|
async fn initialize_stdio(
  conn : StdioConnection,
  client : @mcp_client.McpClient,
) -> Unit raise McpStdioError {
  let init = client.initialize_request()
  write_json_line(conn, init.message)
  let init_id = init.expected_id() catch {
    _ => raise McpStdioError::Protocol("mcp protocol error")
  }
  let init_response = read_response_for_id(conn, expected_id=init_id)
  ignore(
    client.accept_initialize_response(init, init_response) catch {
      _ => raise McpStdioError::Protocol("mcp protocol error")
    },
  )
  write_json_line(conn, client.initialized_notification().message)
}

///|
async fn[X] spawn_stdio(
  group : @async.TaskGroup[X],
  command : String,
  args : Array[String],
  env : Map[String, String],
  cwd : String?,
) -> StdioConnection raise McpStdioError {
  let (reader, stdout_handle) = @process.read_from_process() catch {
    err => raise McpStdioError::SpawnFailed(err.to_string())
  }
  let (stdin_handle, writer) = @process.write_to_process() catch {
    err => raise McpStdioError::SpawnFailed(err.to_string())
  }
  let (stderr_reader, stderr_handle) = @process.read_from_process() catch {
    err => raise McpStdioError::SpawnFailed(err.to_string())
  }
  let process = match cwd {
    None =>
      @process.spawn(
        group,
        command,
        args,
        extra_env=env,
        inherit_env=true,
        stdin=stdin_handle,
        stdout=stdout_handle,
        stderr=stderr_handle,
      ) catch {
        err => raise McpStdioError::SpawnFailed(err.to_string())
      }
    Some(dir) =>
      @process.spawn(
        group,
        command,
        args,
        extra_env=env,
        inherit_env=true,
        stdin=stdin_handle,
        stdout=stdout_handle,
        stderr=stderr_handle,
        cwd=dir.to_string_view(),
      ) catch {
        err => raise McpStdioError::SpawnFailed(err.to_string())
      }
  }
  group.spawn_bg(no_wait=true, () => drain_process_stderr(stderr_reader))
  {
    reader,
    _stdout_handle: stdout_handle,
    _stderr_handle: stderr_handle,
    writer,
    _stdin_handle: stdin_handle,
    process,
    closed: false,
  }
}

///|
async fn write_json_line(
  conn : StdioConnection,
  message : Json,
) -> Unit raise McpStdioError {
  if conn.closed {
    raise McpStdioError::WriteFailed("stdio connection closed")
  }
  conn.writer.write(message.stringify() + "\n") catch {
    err => raise McpStdioError::WriteFailed(err.to_string())
  }
}

///|
async fn read_json_line(conn : StdioConnection) -> Json? raise McpStdioError {
  if conn.closed {
    raise McpStdioError::ReadFailed("stdio connection closed")
  }
  let line = conn.reader.read_until("\n") catch {
    err => raise McpStdioError::ReadFailed(err.to_string())
  }
  match line {
    None => None
    Some(text) =>
      Some(
        @json.parse(text) catch {
          err => raise McpStdioError::InvalidJson(err.to_string())
        },
      )
  }
}

///|
async fn read_response_for_id(
  conn : StdioConnection,
  expected_id~ : Int,
) -> Json raise McpStdioError {
  for ;; {
    let message = read_json_line(conn)
    match message {
      None => raise McpStdioError::UnexpectedEof
      Some(json) =>
        match @mcp_client.mcp_response_id(json) {
          Some(id) if id == expected_id => break json
          _ => continue
        }
    }
  }
}

///|
fn close_stdio(conn : StdioConnection) -> Unit {
  if !conn.closed {
    conn.closed = true
    conn.writer.close()
    conn.reader.close()
    conn.process.cancel()
  }
}
