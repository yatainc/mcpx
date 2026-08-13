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
priv enum StdioProtocolLifecycle {
  Initialize
  Stateless
}

///|
pub struct StdioMcpClient {
  priv conn : StdioConnection
  priv client : @mcp_client.McpClient
  priv lifecycle : StdioProtocolLifecycle
  priv next_request_id : Ref[Int]
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
) -> StdioMcpClient raise McpStdioError {
  let client = new_legacy_client()
  if mode == Stateful {
    let conn = spawn_stdio(group, command, args, env, cwd)
    initialize_stdio(conn, client, response_timeout_ms)
    return new_stdio_mcp_client(conn, client, Initialize, response_timeout_ms)
  }
  let probe_conn = spawn_stdio(group, command, args, env, cwd)
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
    Modern =>
      new_stdio_mcp_client(probe_conn, client, Stateless, response_timeout_ms)
    ModernError(message) => {
      close_stdio(probe_conn)
      raise Protocol(message)
    }
    ExplicitLegacy | TimedOut => {
      close_stdio(probe_conn)
      if mode == Stateless {
        raise Protocol("stateless MCP is not supported")
      }
      let legacy_conn = spawn_stdio(group, command, args, env, cwd)
      initialize_stdio(legacy_conn, client, response_timeout_ms)
      new_stdio_mcp_client(legacy_conn, client, Initialize, response_timeout_ms)
    }
  }
}

///|
fn new_stdio_mcp_client(
  conn : StdioConnection,
  client : @mcp_client.McpClient,
  lifecycle : StdioProtocolLifecycle,
  response_timeout_ms : Int,
) -> StdioMcpClient {
  {
    conn,
    client,
    lifecycle,
    next_request_id: Ref(2),
    response_timeout_ms,
    operation_lock: Semaphore(1),
  }
}

///|
fn new_legacy_client() -> @mcp_client.McpClient {
  @mcp_client.mcp_client(
    client_name=@mcp_client.MCPX_CLIENT_NAME,
    client_version=@mcp_client.MCPX_CLIENT_VERSION,
    protocol_version=@mcp_client.MCP_PROTOCOL_VERSION_LEGACY,
  )
}

///|
pub async fn StdioMcpClient::call_tool(
  self : StdioMcpClient,
  tool_name~ : String,
  arguments~ : Json,
) -> Json raise McpStdioError {
  self.operation_lock.acquire() catch {
    error => raise Protocol(error.to_string())
  }
  defer self.operation_lock.release()
  run_stdio_operation_with_timeout(self.conn, self.response_timeout_ms, () => {
    self.call_tool_unlocked(tool_name~, arguments~)
  })
}

///|
async fn StdioMcpClient::call_tool_unlocked(
  self : StdioMcpClient,
  tool_name~ : String,
  arguments~ : Json,
) -> Json raise McpStdioError {
  match self.lifecycle {
    Initialize => {
      let request = self.client.tool_call_request(name=tool_name, arguments~)
      write_json_line(self.conn, request.message)
      let id = request.expected_id() catch {
        error => raise protocol_error_to_stdio(error)
      }
      let response = read_response_for_id(self.conn, expected_id=id)
      self.client.accept_tool_call_response(request, response) catch {
        error => raise protocol_error_to_stdio(error)
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
          client_name=@mcp_client.MCPX_CLIENT_NAME,
          client_version=@mcp_client.MCPX_CLIENT_VERSION,
        ),
      )
      let response = read_response_for_id(self.conn, expected_id=id)
      match
        @mcp_client.decode_mcp_modern_complete_result(response, expected_id=id) {
        Ok(value) => value
        Err(error) => raise protocol_error_to_stdio(error)
      }
    }
  }
}

///|
pub async fn StdioMcpClient::list_tools(
  self : StdioMcpClient,
  max_pages? : Int = @mcp_client.MCP_TOOL_LIST_MAX_PAGES,
  max_tools? : Int = @mcp_client.MCP_TOOL_LIST_MAX_TOOLS,
) -> Array[@mcp_client.McpToolInfo] raise McpStdioError {
  self.operation_lock.acquire() catch {
    error => raise Protocol(error.to_string())
  }
  defer self.operation_lock.release()
  run_stdio_operation_with_timeout(self.conn, self.response_timeout_ms, () => {
    self.list_tools_unlocked(max_pages~, max_tools~)
  })
}

///|
async fn StdioMcpClient::list_tools_unlocked(
  self : StdioMcpClient,
  max_pages~ : Int,
  max_tools~ : Int,
) -> Array[@mcp_client.McpToolInfo] raise McpStdioError {
  match self.lifecycle {
    Initialize => {
      let request = self.client.tools_list_request()
      write_json_line(self.conn, request.message)
      let id = request.expected_id() catch {
        error => raise protocol_error_to_stdio(error)
      }
      let response = read_response_for_id(self.conn, expected_id=id)
      self.client.accept_tools_list_response(request, response) catch {
        error => raise protocol_error_to_stdio(error)
      }
    }
    Stateless => {
      let pagination = @mcp_client.mcp_tool_pagination()
      let limits = @mcp_client.mcp_tool_list_limits(max_pages~, max_tools~)
      for ;; {
        let cursor = match pagination.begin_page(limits) {
          Ok(value) => value
          Err(error) => raise pagination_error_to_stdio(error)
        }
        let id = take_modern_request_id(self)
        write_json_line(
          self.conn,
          @mcp_client.mcp_tools_list_request(
            id~,
            client_name=@mcp_client.MCPX_CLIENT_NAME,
            client_version=@mcp_client.MCPX_CLIENT_VERSION,
            cursor~,
          ),
        )
        let response = read_response_for_id(self.conn, expected_id=id)
        let page = match
          @mcp_client.decode_mcp_modern_tool_list_page(response, expected_id=id) {
          Ok(value) => value
          Err(error) => raise protocol_error_to_stdio(error)
        }
        match pagination.accept_page(page, limits) {
          Ok(true) => continue
          Ok(false) => break pagination.tools()
          Err(error) => raise pagination_error_to_stdio(error)
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
  mode? : @config.McpConnectionMode = Stateful,
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
    McpStdioError::SpawnFailed(message) => raise SpawnFailed(message)
    McpStdioError::ReadFailed(message) => raise ReadFailed(message)
    McpStdioError::WriteFailed(message) => raise WriteFailed(message)
    McpStdioError::InvalidJson(message) => raise InvalidJson(message)
    McpStdioError::Protocol(message) => raise Protocol(message)
    McpStdioError::Timeout => raise Timeout
    McpStdioError::UnexpectedEof => raise UnexpectedEof
    err => raise Protocol(err.to_string())
  }
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
  max_pages? : Int = @mcp_client.MCP_TOOL_LIST_MAX_PAGES,
  max_tools? : Int = @mcp_client.MCP_TOOL_LIST_MAX_TOOLS,
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
    McpStdioError::SpawnFailed(message) => raise SpawnFailed(message)
    McpStdioError::ReadFailed(message) => raise ReadFailed(message)
    McpStdioError::WriteFailed(message) => raise WriteFailed(message)
    McpStdioError::InvalidJson(message) => raise InvalidJson(message)
    McpStdioError::Protocol(message) => raise Protocol(message)
    McpStdioError::Timeout => raise Timeout
    McpStdioError::UnexpectedEof => raise UnexpectedEof
    err => raise Protocol(err.to_string())
  }
}

///|
fn pagination_error_to_stdio(
  error : @mcp_client.McpToolPaginationError,
) -> McpStdioError {
  match error {
    TooManyPages => Protocol("tools/list exceeds maximum page count")
    TooManyTools => Protocol("tools/list exceeds maximum tool count")
    RepeatedCursor => Protocol("tools/list pagination cursor repeated")
  }
}

///|
fn protocol_error_to_stdio(
  error : @mcp_client.McpProtocolError,
) -> McpStdioError {
  match error {
    InvalidResponse(message) => Protocol(message)
    HeaderMismatch(message) => Protocol("MCP header mismatch: " + message)
    MissingRequiredClientCapability(message) =>
      Protocol("missing required client capability: " + message)
    UnsupportedProtocolVersion(_, supported) =>
      Protocol(
        "unsupported MCP protocol version; supported: " + supported.join(", "),
      )
    RemoteError(code, message) =>
      Protocol("json-rpc error " + code.to_string() + ": " + message)
  }
}

///|
fn take_modern_request_id(client : StdioMcpClient) -> Int {
  let id = client.next_request_id.val
  client.next_request_id.val = id + 1
  id
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
    error => raise protocol_error_to_stdio(error)
  }
  let init_response = read_response_for_id_with_timeout(
    conn,
    expected_id=init_id,
    timeout_ms=response_timeout_ms,
  )
  ignore(
    client.accept_initialize_response(init, init_response) catch {
      error => raise protocol_error_to_stdio(error)
    },
  )
  write_json_line(conn, client.initialized_notification().message)
}
