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
pub extend McpStdioError with Debug::{to_repr}

///|
priv enum StdioProtocolLifecycle {
  Initialize
  Stateless(Json)
}

///|
pub struct StdioMcpClient {
  priv conn : StdioConnection
  priv lifecycle : StdioProtocolLifecycle
  priv mut next_request_id : Int
  priv response_timeout_ms : Int
  priv operation_lock : @async.Semaphore
}

///|
pub async fn[X] stdio_mcp_connect(
  group : @async.TaskGroup[X],
  command~ : String,
  args~ : Array[String],
  env~ : Map[String, String],
  cwd~ : String?,
  mode? : @config.McpConnectionMode = Stateful,
  probe_timeout_ms? : Int = 1000,
  response_timeout_ms? : Int = 30000,
  receive_budget? : @receive.Budget,
) -> StdioMcpClient raise McpStdioError {
  if receive_budget is Some(_) && mode != Stateless {
    raise Protocol("bounded retrieval requires stateless MCP")
  }
  if mode == Stateful {
    let conn = spawn_stdio(group, command, args, env, cwd)
    initialize_stdio(conn, response_timeout_ms)
    return new_stdio_mcp_client(conn, Initialize, response_timeout_ms)
  }
  let probe_conn = spawn_stdio(group, command, args, env, cwd)
  if receive_budget is Some(budget) {
    probe_conn.lines = Some(@receive.Lines::new(probe_conn.reader))
    probe_conn.receive_budget = Some(budget)
  }
  let probe_started_at = @async.now()
  let probe_result = @async.with_timeout(probe_timeout_ms, () => {
    probe_modern_stdio(probe_conn)
  }) catch {
    @async.TimeoutError => TimedOut
    McpStdioError::ReadFailed(message) => {
      let elapsed = @async.now() - probe_started_at
      if elapsed >= probe_timeout_ms.to_int64() {
        TimedOut
      } else {
        ModernError("MCP discovery read failed: " + message)
      }
    }
    McpStdioError::WriteFailed(message) =>
      ModernError("MCP discovery write failed: " + message)
    McpStdioError::InvalidJson(message) =>
      ModernError("invalid MCP discovery JSON: " + message)
    McpStdioError::UnexpectedEof =>
      ModernError("MCP discovery ended unexpectedly")
    McpStdioError::Protocol(message) => ModernError(message)
    McpStdioError::SpawnFailed(message) =>
      ModernError("MCP discovery spawn failed: " + message)
    McpStdioError::Timeout => TimedOut
    error => ModernError(error.to_string())
  }
  match probe_result {
    Modern(capabilities) =>
      new_stdio_mcp_client(
        probe_conn,
        Stateless(capabilities),
        response_timeout_ms,
      )
    ModernError(message) => {
      close_stdio(probe_conn)
      raise Protocol(message)
    }
    ExplicitLegacy | TimedOut => {
      close_stdio(probe_conn)
      if mode == Stateless {
        raise Protocol("stateless MCP is not supported")
      }
      let conn = spawn_stdio(group, command, args, env, cwd)
      initialize_stdio(conn, response_timeout_ms)
      new_stdio_mcp_client(conn, Initialize, response_timeout_ms)
    }
  }
}

///|
fn new_stdio_mcp_client(
  conn : StdioConnection,
  lifecycle : StdioProtocolLifecycle,
  response_timeout_ms : Int,
) -> StdioMcpClient {
  {
    conn,
    lifecycle,
    next_request_id: 2,
    response_timeout_ms,
    operation_lock: Semaphore(1),
  }
}

///|
async fn[T] StdioMcpClient::with_operation(
  self : StdioMcpClient,
  operation : async () -> T,
) -> T raise McpStdioError {
  self.operation_lock.acquire()
  defer self.operation_lock.release()
  let own_budget = self.conn.lines is Some(_) &&
    self.conn.receive_budget is None
  if own_budget {
    self.conn.receive_budget = Some(
      @receive.Budget::new() catch {
        err => raise ReadFailed(err.to_string())
      },
    )
  }
  defer (if own_budget { self.conn.receive_budget = None })
  run_stdio_operation_with_timeout(self.conn, self.response_timeout_ms, () => {
    operation() catch {
      error => raise protocol_error_to_stdio(error)
    }
  })
}

///|
// Called only inside an operation, so request IDs and the stream share one lock.
async fn StdioMcpClient::request(
  self : StdioMcpClient,
  rpc_method : String,
  params : Map[String, Json],
) -> Json {
  let id = self.next_request_id
  self.next_request_id += 1
  let params = match self.lifecycle {
    Initialize => params.to_json()
    Stateless(_) =>
      @protocol.with_mcp_request_meta(
        params,
        @protocol.mcp_request_context(
          protocol=V2026_07_28,
          client_name=@protocol.MCPX_CLIENT_NAME,
          client_version=@protocol.MCPX_CLIENT_VERSION,
        ),
      )
  }
  write_json_line(
    self.conn,
    @protocol.mcp_request(id, rpc_method, Some(params)),
  )
  @protocol.decode_mcp_result(
    read_response_for_id(self.conn, expected_id=id),
    expected_id=id,
  )
}

///|
pub async fn StdioMcpClient::call_tool(
  self : StdioMcpClient,
  tool_name~ : String,
  arguments~ : Json,
) -> Json raise McpStdioError {
  self.with_operation(() => {
    let result = self.request(
      "tools/call",
      @tools.call_params(tool_name, arguments),
    )
    match self.lifecycle {
      Stateless(_) => @protocol.require_complete_result(result)
      Initialize => ()
    }
    result
  })
}

///|
pub async fn StdioMcpClient::list_tools(
  self : StdioMcpClient,
  max_pages? : Int = @tools.MCP_TOOL_LIST_MAX_PAGES,
  max_tools? : Int = @tools.MCP_TOOL_LIST_MAX_TOOLS,
) -> Array[@tools.McpToolInfo] raise McpStdioError {
  self.with_operation(() => {
    match self.lifecycle {
      Initialize =>
        @tools.decode_list_result(
          self.request("tools/list", @tools.list_params()),
        ).tools
      Stateless(_) =>
        @tools.list(
          cursor => self.request("tools/list", @tools.list_params(cursor~)),
          max_pages~,
          max_tools~,
        )
    }
  })
}

///|
pub fn StdioMcpClient::close(self : StdioMcpClient) -> Unit {
  close_stdio(self.conn)
}

///|
async fn[T] with_client(
  operation : async (StdioMcpClient) -> T,
  command~ : String,
  args~ : Array[String],
  env~ : Map[String, String],
  cwd~ : String?,
  mode~ : @config.McpConnectionMode,
  probe_timeout_ms~ : Int,
  response_timeout_ms~ : Int,
) -> T raise McpStdioError {
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
    operation(client)
  }) catch {
    error => raise protocol_error_to_stdio(error)
  }
}

///|
pub async fn stdio_mcp_call_tool(
  command~ : String,
  args~ : Array[String],
  env~ : Map[String, String],
  cwd~ : String?,
  tool_name~ : String,
  arguments~ : Json,
  mode? : @config.McpConnectionMode = Stateful,
  probe_timeout_ms? : Int = 1000,
  response_timeout_ms? : Int = 30000,
) -> Json raise McpStdioError {
  with_client(
    client => client.call_tool(tool_name~, arguments~),
    command~,
    args~,
    env~,
    cwd~,
    mode~,
    probe_timeout_ms~,
    response_timeout_ms~,
  )
}

///|
pub async fn stdio_mcp_list_tools(
  command~ : String,
  args~ : Array[String],
  env~ : Map[String, String],
  cwd~ : String?,
  mode? : @config.McpConnectionMode = Stateful,
  probe_timeout_ms? : Int = 1000,
  response_timeout_ms? : Int = 30000,
  max_pages? : Int = @tools.MCP_TOOL_LIST_MAX_PAGES,
  max_tools? : Int = @tools.MCP_TOOL_LIST_MAX_TOOLS,
) -> Array[@tools.McpToolInfo] raise McpStdioError {
  with_client(
    client => client.list_tools(max_pages~, max_tools~),
    command~,
    args~,
    env~,
    cwd~,
    mode~,
    probe_timeout_ms~,
    response_timeout_ms~,
  )
}

///|
fn protocol_error_to_stdio(error : Error) -> McpStdioError {
  match error {
    @protocol.InvalidResponse(message) | Protocol(message) => Protocol(message)
    @protocol.HeaderMismatch(message) =>
      Protocol("MCP header mismatch: " + message)
    @protocol.MissingRequiredClientCapability(message) =>
      Protocol("missing required client capability: " + message)
    @protocol.UnsupportedProtocolVersion(_, supported) =>
      Protocol(
        "unsupported MCP protocol version; supported: " + supported.join(", "),
      )
    @protocol.RemoteError(code, message) =>
      Protocol("json-rpc error " + code.to_string() + ": " + message)
    SpawnFailed(message) => SpawnFailed(message)
    ReadFailed(message) => ReadFailed(message)
    WriteFailed(message) => WriteFailed(message)
    InvalidJson(message) => InvalidJson(message)
    Timeout => Timeout
    UnexpectedEof => UnexpectedEof
    _ => Protocol(error.to_string())
  }
}

///|
async fn initialize_stdio(
  conn : StdioConnection,
  response_timeout_ms : Int,
) -> Unit raise McpStdioError {
  write_json_line(
    conn,
    @protocol.mcp_initialize_request(
      id=1,
      client_name=@protocol.MCPX_CLIENT_NAME,
      client_version=@protocol.MCPX_CLIENT_VERSION,
      protocol_version=@protocol.MCP_PROTOCOL_VERSION_LEGACY,
    ),
  )
  let response = read_response_for_id_with_timeout(
    conn,
    expected_id=1,
    timeout_ms=response_timeout_ms,
  )
  ignore(
    @protocol.decode_mcp_initialize_result(
      @protocol.decode_mcp_result(response, expected_id=1),
    ) catch {
      error => raise protocol_error_to_stdio(error)
    },
  )
  write_json_line(conn, @protocol.mcp_initialized_notification())
}
