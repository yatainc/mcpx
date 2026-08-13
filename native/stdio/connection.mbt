///|
const MCP_STDIO_MAX_SKIPPED_MESSAGES : Int = 1000

///|
priv enum StdioConnectionState {
  Open
  Poisoned
  Closed
} derive(Eq)

///|
priv struct StdioConnection {
  reader : @process.ReadFromProcess
  _stdout_handle : &@process.ProcessOutput
  _stderr_handle : &@process.ProcessOutput
  writer : @process.WriteToProcess
  _stdin_handle : &@process.ProcessInput
  process : @process.Process
  mut state : StdioConnectionState
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
    state: StdioConnectionState::Open,
  }
}

///|
async fn write_json_line(
  conn : StdioConnection,
  message : Json,
) -> Unit raise McpStdioError {
  ensure_stdio_connection_usable(conn)
  conn.writer.write(message.stringify() + "\n") catch {
    err => raise McpStdioError::WriteFailed(err.to_string())
  }
}

///|
async fn read_json_line(conn : StdioConnection) -> Json? raise McpStdioError {
  ensure_stdio_connection_usable(conn)
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
    @async.TimeoutError => poison_stdio_after_timeout(conn)
    McpStdioError::ReadFailed(message) => {
      let elapsed = @async.now() - started_at
      if elapsed >= timeout_ms.to_int64() {
        poison_stdio_after_timeout(conn)
      }
      raise McpStdioError::ReadFailed(message)
    }
    McpStdioError::InvalidJson(message) =>
      raise McpStdioError::InvalidJson(message)
    McpStdioError::UnexpectedEof => raise McpStdioError::UnexpectedEof
    McpStdioError::Protocol(message) => raise McpStdioError::Protocol(message)
    error => raise McpStdioError::Protocol(error.to_string())
  }
}

///|
async fn read_response_for_id(
  conn : StdioConnection,
  expected_id~ : Int,
) -> Json raise McpStdioError {
  read_response_for_id_with_skip_limit(
    conn,
    expected_id~,
    max_skipped_messages=MCP_STDIO_MAX_SKIPPED_MESSAGES,
  )
}

///|
async fn read_response_for_id_with_skip_limit(
  conn : StdioConnection,
  expected_id~ : Int,
  max_skipped_messages~ : Int,
) -> Json raise McpStdioError {
  let mut skipped = 0
  for ;; {
    let message = read_json_line(conn)
    match message {
      None => raise McpStdioError::UnexpectedEof
      Some(json) =>
        match @mcp_client.mcp_response_id(json) {
          Some(id) if id == expected_id => break json
          _ => {
            if skipped >= max_skipped_messages {
              raise McpStdioError::Protocol(
                "too many messages while awaiting MCP response",
              )
            }
            skipped = skipped + 1
            continue
          }
        }
    }
  }
}

///|
fn[T] poison_stdio_after_timeout(
  conn : StdioConnection,
) -> T raise McpStdioError {
  conn.state = StdioConnectionState::Poisoned
  raise McpStdioError::Timeout
}

///|
fn ensure_stdio_connection_usable(
  conn : StdioConnection,
) -> Unit raise McpStdioError {
  match conn.state {
    StdioConnectionState::Open => ()
    StdioConnectionState::Poisoned =>
      raise McpStdioError::Protocol(
        "stdio connection is unusable after timeout",
      )
    StdioConnectionState::Closed =>
      raise McpStdioError::Protocol("stdio connection is closed")
  }
}

///|
fn close_stdio(conn : StdioConnection) -> Unit {
  if conn.state != StdioConnectionState::Closed {
    conn.state = StdioConnectionState::Closed
    conn.writer.close()
    conn.reader.close()
    conn.process.cancel()
  }
}
