///|
pub fn render_mcpx_command(command : McpxCommand) -> String {
  match command {
    Help => mcpx_help_text()
    Version => "mcpx 0.1.4"
    CallHelp => call_help_text()
    Call(command) => render_call_command(command)
    Info(command) => render_info_command(command)
    SearchHelp => search_help_text()
    Search(command) => render_search_command(command)
    AuthHelp => auth_help_text()
    Auth(command) => render_auth_command(command)
    Daemon(command) => render_daemon_command(command)
  }
}

///|
pub fn mcpx_help_text() -> String {
  (
    #|mcpx — execute MCP tools via CLI
    #|
    #|Workflow:
    #|  0. Search MCP Server (if needed): mcpx search <pattern>
    #|  1. Understand how to use server:  mcpx info <server|url>
    #|  2. Understand how to use tool:    mcpx info <server|url> <tool>
    #|  3. Call tool:                     mcpx call <server|url> <tool> [arguments-json]
    #|
    #|Usage:
    #|  mcpx
    #|  mcpx --help
    #|  mcpx --version
    #|  mcpx info
    #|  mcpx info <server|url> [tool]
    #|  mcpx search <pattern>
    #|  mcpx call <server|url> <tool> [arguments-json]
    #|  mcpx auth <server> [--no-browser] [--json]
    #|  mcpx auth <server> --code <code> --state <state> [--iss <issuer>]
    #|  mcpx daemon
    #|  mcpx daemon <status|stop>
    #|
  )
}

///|
pub fn call_help_text() -> String {
  (
    #|mcpx call
    #|
    #|Usage:
    #|  mcpx call <server|url> <tool> [arguments-json]
    #|
    #|Examples:
    #|  mcpx call github search '{"q":"moonbit"}'
    #|  echo '{"q":"moonbit"}' | mcpx call github search
  )
}

///|
pub fn search_help_text() -> String {
  (
    #|mcpx search
    #|
    #|Usage:
    #|  mcpx search <pattern>
  )
}

///|
pub fn auth_help_text() -> String {
  (
    #|mcpx auth
    #|
    #|Usage:
    #|  mcpx auth <server> [--no-browser] [--json]
    #|  mcpx auth <server> --code <code> --state <state> [--iss <issuer>]
  )
}

///|
pub fn daemon_help_text() -> String {
  (
    #|mcpx daemon
    #|
    #|Usage:
    #|  mcpx daemon
    #|  mcpx daemon <status|stop>
  )
}

///|
fn render_call_command(command : CallCommand) -> String {
  let obj = Map([])
  obj["action"] = Json::string("call")
  obj["server"] = Json::string(command.server)
  match command.url {
    Some(value) => obj["url"] = Json::string(value)
    None => ()
  }
  obj["tool"] = Json::string(command.tool)
  match command.arguments_json {
    Some(arguments) => obj["arguments"] = Json::string(arguments)
    None => ()
  }
  Json::object(obj).stringify()
}

///|
fn render_info_command(command : InfoCommand) -> String {
  let obj = Map([])
  obj["action"] = Json::string("info")
  match command.server {
    Some(value) => obj["server"] = Json::string(value)
    None => ()
  }
  match command.url {
    Some(value) => obj["url"] = Json::string(value)
    None => ()
  }
  match command.tool {
    Some(value) => obj["tool"] = Json::string(value)
    None => ()
  }
  Json::object(obj).stringify()
}

///|
fn render_search_command(command : SearchCommand) -> String {
  let obj = Map([])
  obj["action"] = Json::string("search")
  obj["pattern"] = Json::string(command.pattern)
  Json::object(obj).stringify()
}

///|
fn render_auth_command(command : AuthCommand) -> String {
  let obj = Map([])
  obj["action"] = Json::string("auth")
  obj["server"] = Json::string(command.server)
  obj["noBrowser"] = Json::boolean(command.no_browser)
  obj["json"] = Json::boolean(command.json_output)
  match command.code {
    Some(_) => obj["codeProvided"] = Json::boolean(true)
    None => ()
  }
  match command.state {
    Some(_) => obj["stateProvided"] = Json::boolean(true)
    None => ()
  }
  match command.issuer {
    Some(_) => obj["issuerProvided"] = Json::boolean(true)
    None => ()
  }
  Json::object(obj).stringify()
}

///|
fn render_daemon_command(command : DaemonCommand) -> String {
  match command.mode {
    Help => return daemon_help_text()
    _ => ()
  }
  let obj = Map([])
  obj["action"] = Json::string("daemon")
  obj["mode"] = Json::string(daemon_mode_to_string(command.mode))
  Json::object(obj).stringify()
}

///|
fn daemon_mode_to_string(mode : DaemonMode) -> String {
  match mode {
    Help => "help"
    Status => "status"
    Stop => "stop"
  }
}
