///|
const MCP_STDIO_MAX_SKIPPED_MESSAGES : Int = 1000

///|
priv enum StdioConnectionState {
  Open
  Poisoned(String)
  Closed
} derive(Eq)

///|
priv enum StdioInboundMessage {
  Response(Int, Json)
  RequestOrNotification
  Malformed
}

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
    err => raise SpawnFailed(err.to_string())
  }
  let (stdin_handle, writer) = @process.write_to_process() catch {
    err => raise SpawnFailed(err.to_string())
  }
  let (stderr_reader, stderr_handle) = @process.read_from_process() catch {
    err => raise SpawnFailed(err.to_string())
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
        err => raise SpawnFailed(err.to_string())
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
        err => raise SpawnFailed(err.to_string())
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
    state: Open,
  }
}

///|
async fn write_json_line(
  conn : StdioConnection,
  message : Json,
) -> Unit raise McpStdioError {
  ensure_stdio_connection_usable(conn)
  conn.writer.write(message.stringify() + "\n") catch {
    err => raise WriteFailed(err.to_string())
  }
}

///|
async fn read_json_line(conn : StdioConnection) -> Json? raise McpStdioError {
  ensure_stdio_connection_usable(conn)
  let line = conn.reader.read_until("\n") catch {
    err => raise ReadFailed(err.to_string())
  }
  match line {
    None => None
    Some(text) =>
      Some(
        @json.parse(text) catch {
          err => raise InvalidJson(err.to_string())
        },
      )
  }
}

///|
async fn[T] run_stdio_operation_with_timeout(
  conn : StdioConnection,
  timeout_ms : Int,
  operation : async () -> T,
) -> T raise McpStdioError {
  let started_at = @async.now()
  @async.with_timeout(timeout_ms, operation) catch {
    @async.TimeoutError => poison_stdio_after_timeout(conn)
    McpStdioError::ReadFailed(message) => {
      let elapsed = @async.now() - started_at
      if elapsed >= timeout_ms.to_int64() {
        poison_stdio_after_timeout(conn)
      }
      mark_stdio_poisoned(conn, "transport desynchronization")
      raise ReadFailed(message)
    }
    McpStdioError::SpawnFailed(message) => raise SpawnFailed(message)
    McpStdioError::WriteFailed(message) => {
      mark_stdio_poisoned(conn, "transport desynchronization")
      raise WriteFailed(message)
    }
    McpStdioError::InvalidJson(message) => {
      mark_stdio_poisoned(conn, "transport desynchronization")
      raise InvalidJson(message)
    }
    McpStdioError::UnexpectedEof => {
      mark_stdio_poisoned(conn, "transport desynchronization")
      raise UnexpectedEof
    }
    McpStdioError::Protocol(message) => raise Protocol(message)
    McpStdioError::Timeout => raise Timeout
    error => raise Protocol(error.to_string())
  }
}

///|
async fn read_response_for_id_with_timeout(
  conn : StdioConnection,
  expected_id~ : Int,
  timeout_ms~ : Int,
) -> Json raise McpStdioError {
  run_stdio_operation_with_timeout(conn, timeout_ms, () => {
    read_response_for_id(conn, expected_id~)
  })
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
      None => raise UnexpectedEof
      Some(json) =>
        match classify_stdio_inbound_message(json) {
          Response(id, response) if id == expected_id => break response
          Response(_, _) =>
            poison_stdio_after_desynchronization(
              conn, "unexpected MCP response id",
            )
          Malformed =>
            poison_stdio_after_desynchronization(
              conn, "malformed MCP message while awaiting response",
            )
          RequestOrNotification => {
            if skipped >= max_skipped_messages {
              poison_stdio_after_desynchronization(
                conn, "too many messages while awaiting MCP response",
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
fn classify_stdio_inbound_message(message : Json) -> StdioInboundMessage {
  let obj = match message {
    Object(value) => value
    _ => return Malformed
  }
  if obj.get("jsonrpc") != Some(Json::string("2.0")) {
    return Malformed
  }
  let has_result = obj.get("result") is Some(_)
  let has_error = obj.get("error") is Some(_)
  match obj.get("method") {
    Some(String(_)) if !has_result &&
      !has_error &&
      has_valid_stdio_message_params(obj.get("params")) =>
      match obj.get("id") {
        None => RequestOrNotification
        Some(String(_)) => RequestOrNotification
        Some(id) if decode_stdio_message_id(id) is Some(_) =>
          RequestOrNotification
        _ => Malformed
      }
    None if has_result != has_error =>
      match obj.get("id") {
        Some(id) =>
          match decode_stdio_message_id(id) {
            Some(value) => Response(value, message)
            None => Malformed
          }
        None => Malformed
      }
    _ => Malformed
  }
}

///|
fn has_valid_stdio_message_params(value : Json?) -> Bool {
  match value {
    None | Some(Object(_)) | Some(Array(_)) => true
    _ => false
  }
}

///|
fn decode_stdio_message_id(value : Json) -> Int? {
  match value {
    Number(number, ..) if number.trunc() == number &&
      number >= (-2147483648).to_double() &&
      number <= (2147483647 : Int).to_double() => Some(number.to_int())
    _ => None
  }
}

///|
fn mark_stdio_poisoned(conn : StdioConnection, reason : String) -> Unit {
  if conn.state != Closed {
    conn.state = Poisoned(reason)
  }
}

///|
fn[T] poison_stdio_after_timeout(
  conn : StdioConnection,
) -> T raise McpStdioError {
  mark_stdio_poisoned(conn, "timeout")
  raise Timeout
}

///|
fn[T] poison_stdio_after_desynchronization(
  conn : StdioConnection,
  message : String,
) -> T raise McpStdioError {
  mark_stdio_poisoned(conn, "protocol desynchronization")
  raise Protocol(message)
}

///|
fn ensure_stdio_connection_usable(
  conn : StdioConnection,
) -> Unit raise McpStdioError {
  match conn.state {
    Open => ()
    Poisoned(reason) =>
      raise Protocol("stdio connection is unusable after " + reason)
    Closed => raise Protocol("stdio connection is closed")
  }
}

///|
fn close_stdio(conn : StdioConnection) -> Unit {
  if conn.state != Closed {
    conn.state = Closed
    conn.writer.close()
    conn.reader.close()
    conn.process.cancel()
  }
}
