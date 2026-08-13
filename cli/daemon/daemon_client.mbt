///|
async fn request(
  home~ : String,
  config_home? : String? = None,
  req : Json,
) -> Json raise McpxDaemonError {
  let port = match read_mcpx_daemon_port(home~, config_home~) {
    Some(value) => value
    None => raise Unavailable
  }
  let addr = @socket.Addr::parse("127.0.0.1:\{port}") catch {
    error => raise ConnectFailed(error.to_string())
  }
  let conn = @socket.Tcp::connect(addr) catch {
    error => raise ConnectFailed(error.to_string())
  }
  conn.write(req.stringify() + "\n") catch {
    error => raise ConnectFailed(error.to_string())
  }
  let line = conn.read_until("\n") catch {
    error => raise ConnectFailed(error.to_string())
  }
  conn.close()
  match line {
    None => raise InvalidResponse("empty response")
    Some(text) =>
      @json.parse(text) catch {
        error => raise InvalidResponse(error.to_string())
      }
  }
}

///|
fn decode_request_server(
  obj : Map[String, Json],
) -> Result[@config.McpServerConfig, String] {
  let server_json = match obj.get("server") {
    Some(value) => value
    None => return Err("missing server")
  }
  let wrapped = Json::object({
    "mcpServers": Json::object({ "request": server_json }),
  })
  let config = @config.decode_mcpx_config(wrapped) catch {
    _ => return Err("invalid server")
  }
  match config.servers.get("request") {
    Some(value) => Ok(value)
    None => Err("missing server")
  }
}

///|
fn decode_result(response : Json) -> Json raise McpxDaemonError {
  let obj = expect_response_object(response)
  match obj.get("ok") {
    Some(True) => obj.get("result").unwrap_or(Json::empty_object())
    Some(False) => raise RemoteError(error_message(obj))
    _ => raise InvalidResponse("missing ok")
  }
}

///|
fn decode_tools(
  response : Json,
) -> Array[@mcp_client.McpToolInfo] raise McpxDaemonError {
  let result = decode_result(response)
  let wrapped = Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1.0, repr="1"),
    "result": result,
  })
  match @mcp_client.decode_mcp_tool_list_response(wrapped, expected_id=1) {
    Ok(value) => value
    Err(_) => raise InvalidResponse("invalid tools")
  }
}

///|
fn tool_info_json(tool : @mcp_client.McpToolInfo) -> Json {
  let obj = Map([])
  obj["name"] = Json::string(tool.name)
  match tool.description {
    Some(value) => obj["description"] = Json::string(value)
    None => ()
  }
  obj["inputSchema"] = tool.input_schema
  match tool.output_schema {
    Some(value) => obj["outputSchema"] = value
    None => ()
  }
  Json::object(obj)
}

///|
fn expect_response_object(
  response : Json,
) -> Map[String, Json] raise McpxDaemonError {
  match response {
    Object(obj) => obj
    _ => raise InvalidResponse("response must be object")
  }
}

///|
fn ok_response(result : Json) -> Json {
  Json::object({ "ok": Json::boolean(true), "result": result })
}

///|
fn error_response(message : String) -> Json {
  Json::object({ "ok": Json::boolean(false), "error": Json::string(message) })
}

///|
fn error_message(obj : Map[String, Json]) -> String {
  match obj.get("error") {
    Some(String(value)) => value
    _ => "daemon error"
  }
}

///|
fn string_field(obj : Map[String, Json], key : String) -> String? {
  match obj.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn write_daemon_state(
  home~ : String,
  config_home? : String? = None,
  port~ : Int,
) -> Unit raise McpxDaemonError {
  let path = mcpx_daemon_state_path(home~, config_home~)
  let body = Json::object({
    "port": Json::number(Double::from_int(port), repr=port.to_string()),
  }).stringify()
  @storage.secure_write_private_atomic(path, body) catch {
    _ => raise Unavailable
  }
}

///|
fn remove_daemon_state(home~ : String, config_home? : String? = None) -> Unit {
  @fs.remove_file(mcpx_daemon_state_path(home~, config_home~)) catch {
    _ => ()
  }
}

///|
async fn wait_for_daemon_state_removed(
  home~ : String,
  config_home? : String? = None,
) -> Bool {
  let mut elapsed = 0
  while elapsed < 6000 {
    if read_mcpx_daemon_port(home~, config_home~) is None {
      return true
    }
    @async.sleep(50) catch {
      _ => return false
    }
    elapsed = elapsed + 50
  }
  read_mcpx_daemon_port(home~, config_home~) is None
}
