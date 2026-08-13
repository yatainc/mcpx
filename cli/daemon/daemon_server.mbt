///|
async fn handle_conn(
  conn : @socket.Tcp,
  group : @async.TaskGroup[Unit],
  pool : DaemonPool,
) -> Unit {
  let line = conn.read_until("\n") catch { _ => None }
  let (response, should_stop) = match line {
    None => (error_response("empty request"), false)
    Some(text) => handle_request(text, group, pool)
  }
  conn.write(response.stringify() + "\n") catch {
    _ => ()
  }
  conn.close()
  if should_stop {
    raise McpxDaemonStop
  }
}

///|
async fn handle_request(
  text : String,
  group : @async.TaskGroup[Unit],
  pool : DaemonPool,
) -> (Json, Bool) {
  let req = @json.parse(text) catch {
    err => return (error_response(err.to_string()), false)
  }
  let obj = match req {
    Object(value) => value
    _ => return (error_response("request must be object"), false)
  }
  let op = match obj.get("op") {
    Some(String(value)) => value
    _ => ""
  }
  match op {
    "ping" => (ok_response(Json::empty_object()), false)
    "stop" => (ok_response(Json::empty_object()), true)
    "call_tool" => (handle_call_tool(obj, group, pool), false)
    "list_tools" => (handle_list_tools(obj, group, pool), false)
    _ => (error_response("unknown op"), false)
  }
}

///|
async fn handle_call_tool(
  obj : Map[String, Json],
  group : @async.TaskGroup[Unit],
  pool : DaemonPool,
) -> Json {
  let key = string_field(obj, "key").unwrap_or("")
  let tool_name = string_field(obj, "tool").unwrap_or("")
  let arguments = obj.get("args").unwrap_or(Json::empty_object())
  let server = match decode_request_server(obj) {
    Ok(value) => value
    Err(message) => return error_response(message)
  }
  let result : Result[Json, _] = try
    ({
      let entry = pool.entry(group, key, server)
      entry.val.mutex.acquire()
      entry.val.mark_used()
      defer {
        entry.val.mark_used()
        entry.val.mutex.release()
      }
      entry.val.client.call_tool(tool_name~, arguments~)
    })
    |> Ok
  catch {
    error => Err(error)
  }
  match result {
    Ok(value) => ok_response(value)
    Err(error) => error_response(error.to_string())
  }
}

///|
async fn handle_list_tools(
  obj : Map[String, Json],
  group : @async.TaskGroup[Unit],
  pool : DaemonPool,
) -> Json {
  let key = string_field(obj, "key").unwrap_or("")
  let server = match decode_request_server(obj) {
    Ok(value) => value
    Err(message) => return error_response(message)
  }
  let result : Result[Array[@mcp_client.McpToolInfo], _] = try
    ({
      let entry = pool.entry(group, key, server)
      entry.val.mutex.acquire()
      entry.val.mark_used()
      defer {
        entry.val.mark_used()
        entry.val.mutex.release()
      }
      entry.val.client.list_tools()
    })
    |> Ok
  catch {
    error => Err(error)
  }
  match result {
    Ok(tools) =>
      ok_response(
        Json::object({ "tools": Json::array(tools.map(tool_info_json)) }),
      )
    Err(error) => error_response(error.to_string())
  }
}
