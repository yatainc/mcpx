///|
const MAX_TOOL_LIST_PAGES : Int = 1000

///|
const MAX_TOOL_LIST_TOOLS : Int = 100000

///|
pub suberror McpStdioError {
  SpawnFailed(String)
  ReadFailed(String)
  WriteFailed(String)
  InvalidJson(String)
  Protocol(String)
  Timeout
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
priv enum StdioProbeOutcome {
  Modern
  ModernError(String)
  Legacy
}

///|
pub struct StdioMcpClient {
  priv conn : StdioConnection
  client : @mcp_client.McpClient
  lifecycle : StdioProtocolLifecycle
  next_request_id : Ref[Int]
  response_timeout_ms : Int
}

///|
pub async fn[X] stdio_mcp_connect(
  group : @async.TaskGroup[X],
  command~ : String,
  args~ : Array[String],
  env~ : Map[String, String],
  cwd~ : String?,
  mode? : @config.McpConnectionMode = @config.McpConnectionMode::Stateful,
  probe_timeout_ms? : Int = 1000,
  response_timeout_ms? : Int = 30000,
) -> StdioMcpClient raise McpStdioError {
  let client = new_legacy_client()
  if mode == @config.McpConnectionMode::Stateful {
    let conn = spawn_stdio(group, command, args, env, cwd)
    initialize_stdio(conn, client, response_timeout_ms)
    return {
      conn,
      client,
      lifecycle: StdioProtocolLifecycle::Initialize,
      next_request_id: Ref(2),
      response_timeout_ms,
    }
  }
  let probe_conn = spawn_stdio(group, command, args, env, cwd)
  let probe_result : Result[StdioProbeOutcome, Error] = try
    @async.with_timeout(probe_timeout_ms, () => probe_modern_stdio(probe_conn))
    |> Ok
  catch {
    error => Err(error)
  }
  match probe_result {
    Ok(StdioProbeOutcome::Modern) =>
      {
        conn: probe_conn,
        client,
        lifecycle: StdioProtocolLifecycle::Stateless,
        next_request_id: Ref(2),
        response_timeout_ms,
      }
    Ok(StdioProbeOutcome::ModernError(message)) => {
      close_stdio(probe_conn)
      raise McpStdioError::Protocol(message)
    }
    Ok(StdioProbeOutcome::Legacy) | Err(_) => {
      close_stdio(probe_conn)
      if mode == @config.McpConnectionMode::Stateless {
        raise McpStdioError::Protocol("stateless MCP is not supported")
      }
      let legacy_conn = spawn_stdio(group, command, args, env, cwd)
      initialize_stdio(legacy_conn, client, response_timeout_ms)
      {
        conn: legacy_conn,
        client,
        lifecycle: StdioProtocolLifecycle::Initialize,
        next_request_id: Ref(2),
        response_timeout_ms,
      }
    }
  }
}

///|
fn new_legacy_client() -> @mcp_client.McpClient {
  @mcp_client.mcp_client(
    client_name="mcpx",
    client_version="0.1.4",
    protocol_version=@mcp_client.MCP_PROTOCOL_VERSION_LEGACY,
  )
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
      let response = read_response_for_id_with_timeout(
        self.conn,
        expected_id=id,
        timeout_ms=self.response_timeout_ms,
      )
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
      let response = read_response_for_id_with_timeout(
        self.conn,
        expected_id=id,
        timeout_ms=self.response_timeout_ms,
      )
      match
        @mcp_client.decode_mcp_complete_result(
          response,
          expected_id=id,
          require_result_type=true,
        ) {
        Ok(value) => value
        Err(_) => raise McpStdioError::Protocol("mcp protocol error")
      }
    }
  }
}

///|
pub async fn StdioMcpClient::list_tools(
  self : StdioMcpClient,
  max_pages? : Int = MAX_TOOL_LIST_PAGES,
  max_tools? : Int = MAX_TOOL_LIST_TOOLS,
) -> Array[@mcp_client.McpToolInfo] raise McpStdioError {
  match self.lifecycle {
    Initialize => {
      let request = self.client.tools_list_request()
      write_json_line(self.conn, request.message)
      let id = request.expected_id() catch {
        _ => raise McpStdioError::Protocol("mcp protocol error")
      }
      let response = read_response_for_id_with_timeout(
        self.conn,
        expected_id=id,
        timeout_ms=self.response_timeout_ms,
      )
      self.client.accept_tools_list_response(request, response) catch {
        _ => raise McpStdioError::Protocol("mcp protocol error")
      }
    }
    Stateless => {
      let tools = []
      let seen_cursors : Array[String] = []
      let mut cursor : String? = None
      let mut page_count = 0
      for ;; {
        if page_count >= max_pages {
          raise McpStdioError::Protocol("tools/list exceeds maximum page count")
        }
        page_count = page_count + 1
        let id = take_modern_request_id(self)
        write_json_line(
          self.conn,
          @mcp_client.mcp_tools_list_request(
            id~,
            client_name="mcpx",
            client_version="0.1.4",
            cursor~,
          ),
        )
        let response = read_response_for_id_with_timeout(
          self.conn,
          expected_id=id,
          timeout_ms=self.response_timeout_ms,
        )
        let page = match
          @mcp_client.decode_mcp_tool_list_page(
            response,
            expected_id=id,
            require_result_type=true,
          ) {
          Ok(value) => value
          Err(_) => raise McpStdioError::Protocol("mcp protocol error")
        }
        if tools.length() + page.tools.length() > max_tools {
          raise McpStdioError::Protocol("tools/list exceeds maximum tool count")
        }
        for tool in page.tools {
          tools.push(tool)
        }
        match page.next_cursor {
          None => break tools
          Some(next) => {
            if seen_cursors.contains(next) {
              raise McpStdioError::Protocol(
                "tools/list pagination cursor repeated",
              )
            }
            seen_cursors.push(next)
            cursor = Some(next)
          }
        }
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
  probe_timeout_ms? : Int = 1000,
  response_timeout_ms? : Int = 30000,
) -> Json raise McpStdioError {
  @async.with_task_group(group => {
    let client = stdio_mcp_connect(
      group,
      command~,
      args~,
      env~,
      cwd~,
      mode~,
      probe_timeout_ms~,
      response_timeout_ms~,
    )
    defer client.close()
    client.call_tool(tool_name~, arguments~)
  }) catch {
    McpStdioError::SpawnFailed(message) =>
      raise McpStdioError::SpawnFailed(message)
    McpStdioError::ReadFailed(message) =>
      raise McpStdioError::ReadFailed(message)
    McpStdioError::WriteFailed(message) =>
      raise McpStdioError::WriteFailed(message)
    McpStdioError::InvalidJson(message) =>
      raise McpStdioError::InvalidJson(message)
    McpStdioError::Protocol(message) => raise McpStdioError::Protocol(message)
    McpStdioError::Timeout => raise McpStdioError::Timeout
    McpStdioError::UnexpectedEof => raise McpStdioError::UnexpectedEof
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
  probe_timeout_ms? : Int = 1000,
  response_timeout_ms? : Int = 30000,
  max_pages? : Int = MAX_TOOL_LIST_PAGES,
  max_tools? : Int = MAX_TOOL_LIST_TOOLS,
) -> Array[@mcp_client.McpToolInfo] raise McpStdioError {
  @async.with_task_group(group => {
    let client = stdio_mcp_connect(
      group,
      command~,
      args~,
      env~,
      cwd~,
      mode~,
      probe_timeout_ms~,
      response_timeout_ms~,
    )
    defer client.close()
    client.list_tools(max_pages~, max_tools~)
  }) catch {
    McpStdioError::SpawnFailed(message) =>
      raise McpStdioError::SpawnFailed(message)
    McpStdioError::ReadFailed(message) =>
      raise McpStdioError::ReadFailed(message)
    McpStdioError::WriteFailed(message) =>
      raise McpStdioError::WriteFailed(message)
    McpStdioError::InvalidJson(message) =>
      raise McpStdioError::InvalidJson(message)
    McpStdioError::Protocol(message) => raise McpStdioError::Protocol(message)
    McpStdioError::Timeout => raise McpStdioError::Timeout
    McpStdioError::UnexpectedEof => raise McpStdioError::UnexpectedEof
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
async fn probe_modern_stdio(
  conn : StdioConnection,
) -> StdioProbeOutcome raise McpStdioError {
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
        StdioProbeOutcome::Modern
      } else {
        StdioProbeOutcome::ModernError("MCP 2026-07-28 is not supported")
      }
    Err(@mcp_client.McpProtocolError::RemoteError(code, message)) =>
      if is_recognized_modern_stdio_error(code) {
        StdioProbeOutcome::ModernError(
          "modern MCP discovery error " + code.to_string() + ": " + message,
        )
      } else {
        StdioProbeOutcome::Legacy
      }
    Err(@mcp_client.McpProtocolError::UnsupportedProtocolVersion(_, supported)) =>
      StdioProbeOutcome::ModernError(
        "unsupported MCP protocol version; supported: " + supported.join(", "),
      )
    Err(@mcp_client.McpProtocolError::HeaderMismatch(message)) =>
      StdioProbeOutcome::ModernError("MCP header mismatch: " + message)
    Err(@mcp_client.McpProtocolError::MissingRequiredClientCapability(message)) =>
      StdioProbeOutcome::ModernError(
        "missing required client capability: " + message,
      )
    Err(@mcp_client.McpProtocolError::InvalidResponse(message)) =>
      StdioProbeOutcome::ModernError(
        "invalid MCP discovery response: " + message,
      )
  }
}

///|
fn is_recognized_modern_stdio_error(code : Int) -> Bool {
  code == -32020 || code == -32021 || code == -32022
}

///|
async fn initialize_stdio(
  conn : StdioConnection,
  client : @mcp_client.McpClient,
  response_timeout_ms : Int,
) -> Unit raise McpStdioError {
  let init = client.initialize_request()
  write_json_line(conn, init.message)
  let init_id = init.expected_id() catch {
    _ => raise McpStdioError::Protocol("mcp protocol error")
  }
  let init_response = read_response_for_id_with_timeout(
    conn,
    expected_id=init_id,
    timeout_ms=response_timeout_ms,
  )
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
async fn read_response_for_id_with_timeout(
  conn : StdioConnection,
  expected_id~ : Int,
  timeout_ms~ : Int,
) -> Json raise McpStdioError {
  let started_at = @async.now()
  @async.with_timeout(timeout_ms, () => read_response_for_id(conn, expected_id~)) catch {
    @async.TimeoutError => raise McpStdioError::Timeout
    McpStdioError::ReadFailed(message) => {
      let elapsed = @async.now() - started_at
      if elapsed >= timeout_ms.to_int64() {
        raise McpStdioError::Timeout
      }
      raise McpStdioError::ReadFailed(message)
    }
    McpStdioError::InvalidJson(message) =>
      raise McpStdioError::InvalidJson(message)
    McpStdioError::UnexpectedEof => raise McpStdioError::UnexpectedEof
    error => raise McpStdioError::Protocol(error.to_string())
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
