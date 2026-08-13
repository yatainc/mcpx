///|
fn needs_host_read_credentials(
  server_name : String,
  credentials_path : String,
  cache_key : String,
) -> String {
  let obj = Map([])
  obj["status"] = Json::string("needs_host")
  obj["state"] = read_credentials_state(
    server_name, credentials_path, cache_key,
  )
  obj["actions"] = Json::array([
    @auth.credentials_lookup_action(credentials_path~).to_json(),
  ])
  Json::object(obj).stringify()
}

///|
fn needs_host(state : Json, actions : Array[@host.HostAction]) -> String {
  let obj = Map([])
  obj["status"] = Json::string("needs_host")
  obj["state"] = state
  obj["actions"] = Json::array(actions.map(action => action.to_json()))
  Json::object(obj).stringify()
}

///|
fn copy_optional_fields(
  source~ : Map[String, Json],
  target~ : Map[String, Json],
  fields~ : Array[String],
) -> Unit {
  for field in fields {
    match source.get(field) {
      Some(value) => target[field] = value
      None => ()
    }
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
fn mcp_http_headers() -> Map[String, String] {
  {
    "content-type": "application/json",
    "accept": "application/json, text/event-stream",
  }
}

///|
fn read_credentials_state(
  server_name : String,
  credentials_path : String,
  cache_key : String,
) -> Json {
  let state = Map([])
  state["phase"] = Json::string("read_credentials")
  state["serverName"] = Json::string(server_name)
  state["credentialsPath"] = Json::string(credentials_path)
  state["cacheKey"] = Json::string(cache_key)
  Json::object(state)
}
