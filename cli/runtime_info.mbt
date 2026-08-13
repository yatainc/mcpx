///|
async fn run_info(
  command : InfoCommand,
  home : String,
  config_home : String?,
) -> String {
  match command.server {
    None => return run_info_servers(home, config_home)
    Some(_) => ()
  }
  let target_server = command.server.unwrap()
  match command.url {
    Some(url) =>
      return run_info_url(
        server_name=target_server,
        url~,
        headers=Map([]),
        tool=command.tool,
        filter_server=None,
      )
    None => ()
  }
  let paths = @app_paths.mcpx_app_paths(home, config_home~)
  let config = @storage.load_mcpx_config_or_empty(paths.servers_config)
  match config.servers.get(target_server) {
    None => error_result("server not found: " + target_server)
    Some(server) => {
      let resolved_server = match
        resolve_runtime_server(server, paths.env_file) {
        Ok(value) => value
        Err(message) => return error_result(message)
      }
      match resolved_server.transport {
        @config.ServerTransport::Stdio =>
          if is_keep_alive_server(resolved_server) {
            run_info_daemon(
              target_server,
              resolved_server,
              home,
              config_home,
              command.tool,
            )
          } else {
            run_info_stdio(target_server, resolved_server, command.tool)
          }
        @config.ServerTransport::Http =>
          match resolved_server.url {
            None => error_result("server has no url: " + target_server)
            Some(url) => {
              let headers = match
                call_headers_with_cached_auth(
                  server_name=target_server,
                  server_url=url,
                  server=resolved_server,
                  credentials_path=paths.credentials_file,
                ) {
                Ok(value) => value
                Err(message) => return error_result(message)
              }
              run_info_url(
                server_name=target_server,
                url~,
                headers~,
                tool=command.tool,
                filter_server=Some(resolved_server),
                mode=@config.effective_connection_mode(resolved_server),
              )
            }
          }
      }
    }
  }
}

///|
fn run_info_servers(home : String, config_home : String?) -> String {
  let paths = @app_paths.mcpx_app_paths(home, config_home~)
  let config = @storage.load_mcpx_config_or_empty(paths.servers_config) catch {
    _ => return error_result("failed to load config")
  }
  if config.servers.is_empty() {
    return "No servers configured.\nConfig: " + paths.servers_config
  }
  let lines = ["Servers:"]
  let name_width = max_server_name_width(config.servers)
  for name, server in config.servers {
    match first_description_line(server.description) {
      Some(description) =>
        lines.push(
          "  " +
          pad_right(name, name_width) +
          "  " +
          truncate_chars(description, 60),
        )
      None => lines.push("  " + name)
    }
  }
  lines.join("\n")
}

///|
fn max_server_name_width(servers : Map[String, @config.McpServerConfig]) -> Int {
  let mut width = 0
  for name, _ in servers {
    if name.length() > width {
      width = name.length()
    }
  }
  width
}

///|
fn pad_right(text : String, width : Int) -> String {
  if text.length() >= width {
    return text
  }
  let out = StringBuilder::new(size_hint=width)
  out.write_string(text)
  for _ in text.length()..<width {
    out.write_char(' ')
  }
  out.to_string()
}

///|
fn truncate_chars(text : String, max_chars : Int) -> String {
  let chars = text.to_array()
  if chars.length() <= max_chars {
    return text
  }
  if max_chars <= 3 {
    let out = StringBuilder::new(size_hint=max_chars)
    for _ in 0..<max_chars {
      out.write_char('.')
    }
    return out.to_string()
  }
  let out = StringBuilder::new(size_hint=max_chars)
  for i in 0..<(max_chars - 3) {
    out.write_char(chars[i])
  }
  out.write_string("...")
  out.to_string()
}

///|
fn server_transport_text(server : @config.McpServerConfig) -> String {
  match server.transport {
    @config.ServerTransport::Http => "http"
    @config.ServerTransport::Stdio => "stdio"
  }
}

///|
async fn run_info_daemon(
  server_name : String,
  server : @config.McpServerConfig,
  home : String,
  config_home : String?,
  tool : String?,
) -> String {
  let tools = @mcpx_daemon.daemon_list_tools(
    home~,
    config_home~,
    key=daemon_pool_key(server_name, server),
    server~,
  ) catch {
    _ => return error_result("mcp daemon error")
  }
  info_tools_result(server_name, tools, tool, filter_server=Some(server))
}

///|
async fn run_info_stdio(
  server_name : String,
  server : @config.McpServerConfig,
  tool : String?,
) -> String {
  let executable = match server.command {
    Some(value) => value
    None => return error_result("server has no command: " + server_name)
  }
  let tools = @mcp_stdio.stdio_mcp_list_tools(
    command=executable,
    args=server.args,
    env=server.env,
    cwd=server.cwd,
    mode=@config.effective_connection_mode(server),
  ) catch {
    _ => return error_result("mcp stdio error")
  }
  info_tools_result(server_name, tools, tool, filter_server=Some(server))
}

///|
async fn run_info_url(
  server_name~ : String,
  url~ : String,
  headers~ : Map[String, String],
  tool~ : String?,
  filter_server~ : @config.McpServerConfig?,
  mode? : @config.McpConnectionMode = @config.McpConnectionMode::Auto,
) -> String {
  let tools = @mcp_http.http_mcp_list_tools(url~, headers~, mode~) catch {
    error => return mcp_http_error_result(server_name, error)
  }
  info_tools_result(server_name, tools, tool, filter_server~)
}

///|
fn info_tools_result(
  server_name : String,
  tools : Array[@mcp_client.McpToolInfo],
  tool : String?,
  filter_server~ : @config.McpServerConfig?,
) -> String {
  let filtered = match filter_server {
    None => tools
    Some(server) => @config.filter_tools(server, tools, tool => tool.name)
  }
  match tool {
    None => tools_text_result(server_name, filtered)
    Some(tool_name) =>
      match find_tool(filtered, tool_name) {
        None => error_result("tool not found: " + tool_name)
        Some(found) => tool_schema_result(server_name, found)
      }
  }
}

///|
fn find_tool(
  tools : Array[@mcp_client.McpToolInfo],
  tool_name : String,
) -> @mcp_client.McpToolInfo? {
  for tool in tools {
    if tool.name == tool_name {
      return Some(tool)
    }
  }
  None
}

///|
fn tools_text_result(
  server_name : String,
  tools : Array[@mcp_client.McpToolInfo],
) -> String {
  if tools.is_empty() {
    ignore(server_name)
    return "Tools\n  (none)"
  }
  ignore(server_name)
  let lines = ["Tools"]
  for tool in tools {
    append_tool_lines(lines, server_name, tool, include_server=false)
  }
  lines.join("\n")
}

///|
fn append_tool_lines(
  lines : Array[String],
  server_name : String,
  tool : @mcp_client.McpToolInfo,
  include_server~ : Bool,
) -> Unit {
  let prefix = if include_server { server_name + "/" } else { "" }
  lines.push("  " + prefix + tool_signature(tool))
  match first_description_line(tool.description) {
    Some(summary) => lines.push("    " + summary)
    None => ()
  }
}

///|
fn tool_schema_result(
  server_name : String,
  tool : @mcp_client.McpToolInfo,
) -> String {
  let lines = ["Tool: " + server_name + "/" + tool.name]
  match first_description_line(tool.description) {
    Some(summary) => {
      lines.push("")
      lines.push(summary)
    }
    None => ()
  }
  lines.push("")
  lines.push("Arguments:")
  append_schema_argument_lines(lines, tool.input_schema)
  if contains_json_schema_2020_12_construct(tool.input_schema) {
    lines.push("")
    lines.push("JSON Schema 2020-12:")
    lines.push(tool.input_schema.stringify(indent=2))
  }
  lines.join("\n")
}

///|
fn tool_signature(tool : @mcp_client.McpToolInfo) -> String {
  let args = schema_required_args(tool.input_schema)
  tool.name + "(" + args.join(", ") + ")"
}

///|
fn first_description_line(description : String?) -> String? {
  match description {
    None => None
    Some(text) => {
      for part_view in text.split("\n") {
        let part = part_view.trim().to_owned()
        if !part.is_empty() {
          return Some(part)
        }
      }
      None
    }
  }
}

///|
fn schema_required_args(schema : Json) -> Array[String] {
  match schema {
    Object(obj) =>
      match obj.get("required") {
        Some(Array(values)) => {
          let args = []
          for value in values {
            match value {
              String(name) => args.push(name)
              _ => ()
            }
          }
          args
        }
        _ => []
      }
    _ => []
  }
}

///|
fn append_schema_argument_lines(lines : Array[String], schema : Json) -> Unit {
  match schema {
    Object(obj) =>
      match obj.get("properties") {
        Some(Object(properties)) =>
          if properties.is_empty() {
            lines.push("  (none)")
          } else {
            let required = schema_required_args(schema)
            for name, value in properties {
              let marker = if required.contains(name) {
                " required"
              } else {
                ""
              }
              let type_text = schema_type_text(value)
              if type_text.is_empty() {
                lines.push("  " + name + marker)
              } else {
                lines.push("  " + name + "  " + type_text + marker)
              }
              match schema_description_text(value) {
                Some(description) => lines.push("    " + description)
                None => ()
              }
            }
          }
        _ => lines.push("  (none)")
      }
    _ => lines.push("  (none)")
  }
}

///|
fn contains_json_schema_2020_12_construct(schema : Json) -> Bool {
  match schema {
    Object(obj) => {
      let keywords = [
        "$defs", "$dynamicAnchor", "$dynamicRef", "prefixItems", "unevaluatedItems",
        "unevaluatedProperties", "dependentRequired", "dependentSchemas", "minContains",
        "maxContains",
      ]
      if keywords.any(keyword => obj.contains(keyword)) {
        return true
      }
      for _, value in obj {
        if contains_json_schema_2020_12_construct(value) {
          return true
        }
      }
      false
    }
    Array(values) => values.any(contains_json_schema_2020_12_construct)
    _ => false
  }
}

///|
fn schema_type_text(schema : Json) -> String {
  match schema {
    Object(obj) =>
      match obj.get("type") {
        Some(String(value)) => value
        _ => ""
      }
    _ => ""
  }
}

///|
fn schema_description_text(schema : Json) -> String? {
  match schema {
    Object(obj) =>
      match obj.get("description") {
        Some(String(value)) => first_description_line(Some(value))
        _ => None
      }
    _ => None
  }
}
