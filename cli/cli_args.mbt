///|
pub(all) enum McpxCommand {
  Help
  Version
  CallHelp
  Call(CallCommand)
  Info(InfoCommand)
  SearchHelp
  Search(SearchCommand)
  AuthHelp
  Auth(AuthCommand)
  Daemon(DaemonCommand)
} derive(Debug)

///|
pub struct CallCommand {
  server : String
  url : String?
  tool : String
  arguments_json : String?
} derive(Debug)

///|
pub struct InfoCommand {
  server : String?
  url : String?
  tool : String?
} derive(Debug)

///|
pub struct SearchCommand {
  pattern : String
} derive(Debug)

///|
pub struct AuthCommand {
  server : String
  no_browser : Bool
  json_output : Bool
  code : String?
  state : String?
  issuer : String?
} derive(Debug)

///|
pub struct DaemonCommand {
  mode : DaemonMode
} derive(Debug)

///|
pub(all) enum DaemonMode {
  Help
  Status
  Stop
} derive(Debug)

///|
pub(all) enum CliParseError {
  MissingArgument(String)
  InvalidTarget(String)
  UnknownOption(String)
  UnknownCommand(String)
} derive(Debug)

///|
pub fn parse_mcpx_args(
  args : Array[String],
) -> Result[McpxCommand, CliParseError] {
  match args.get(0) {
    None => Ok(McpxCommand::Help)
    Some("--help") =>
      if args.length() > 1 {
        Err(CliParseError::UnknownOption(args[1]))
      } else {
        Ok(McpxCommand::Help)
      }
    Some("--version") =>
      if args.length() > 1 {
        Err(CliParseError::UnknownOption(args[1]))
      } else {
        Ok(McpxCommand::Version)
      }
    Some("call") => parse_call_command(args)
    Some("info") => parse_info_command(args)
    Some("search") => parse_search_command(args)
    Some("auth") => parse_auth_command(args)
    Some("daemon") => parse_daemon_command(args)
    Some(command) => Err(CliParseError::UnknownCommand(command))
  }
}

///|
fn parse_call_command(
  args : Array[String],
) -> Result[McpxCommand, CliParseError] {
  match (args.get(1), args.get(2)) {
    (None, _) => Ok(McpxCommand::CallHelp)
    (Some("--url"), _) => Err(CliParseError::InvalidTarget("--url"))
    (_, None) => Err(CliParseError::MissingArgument("tool"))
    (Some(target), Some(tool)) =>
      if args.length() > 4 {
        Err(CliParseError::UnknownOption(args[4]))
      } else {
        let (server, url) = target_server_url(target)
        Ok(
          McpxCommand::Call({ server, url, tool, arguments_json: args.get(3) }),
        )
      }
  }
}

///|
fn parse_info_command(
  args : Array[String],
) -> Result[McpxCommand, CliParseError] {
  match args.get(1) {
    None => Ok(McpxCommand::Info({ server: None, url: None, tool: None }))
    Some("--url") => Err(CliParseError::InvalidTarget("--url"))
    Some(target) =>
      if args.length() > 3 {
        Err(CliParseError::UnknownOption(args[3]))
      } else {
        let (server, url) = target_server_url(target)
        Ok(McpxCommand::Info({ server: Some(server), url, tool: args.get(2) }))
      }
  }
}

///|
fn parse_search_command(
  args : Array[String],
) -> Result[McpxCommand, CliParseError] {
  match args.get(1) {
    None => Ok(McpxCommand::SearchHelp)
    Some(pattern) =>
      if args.length() > 2 {
        Err(CliParseError::UnknownOption(args[2]))
      } else {
        Ok(McpxCommand::Search({ pattern, }))
      }
  }
}

///|
fn parse_auth_command(
  args : Array[String],
) -> Result[McpxCommand, CliParseError] {
  match args.get(1) {
    None => Ok(McpxCommand::AuthHelp)
    Some(server) => {
      let mut no_browser = false
      let mut json_output = false
      let mut code : String? = None
      let mut state : String? = None
      let mut issuer : String? = None
      for i = 2; i < args.length(); {
        match args[i] {
          "--no-browser" => no_browser = true
          "--json" => json_output = true
          "--code" =>
            match args.get(i + 1) {
              Some(value) => {
                code = Some(value)
                continue i + 2
              }
              None => return Err(CliParseError::MissingArgument("code"))
            }
          "--state" =>
            match args.get(i + 1) {
              Some(value) => {
                state = Some(value)
                continue i + 2
              }
              None => return Err(CliParseError::MissingArgument("state"))
            }
          "--iss" =>
            match args.get(i + 1) {
              Some(value) => {
                issuer = Some(value)
                continue i + 2
              }
              None => return Err(CliParseError::MissingArgument("iss"))
            }
          option => return Err(CliParseError::UnknownOption(option))
        }
        continue i + 1
      }
      Ok(
        McpxCommand::Auth({
          server,
          no_browser,
          json_output,
          code,
          state,
          issuer,
        }),
      )
    }
  }
}

///|
fn parse_daemon_command(
  args : Array[String],
) -> Result[McpxCommand, CliParseError] {
  match args.get(1) {
    None =>
      if args.length() > 2 {
        Err(CliParseError::UnknownOption(args[2]))
      } else {
        Ok(McpxCommand::Daemon({ mode: DaemonMode::Help }))
      }
    Some("status") =>
      if args.length() > 2 {
        Err(CliParseError::UnknownOption(args[2]))
      } else {
        Ok(McpxCommand::Daemon({ mode: DaemonMode::Status }))
      }
    Some("stop") =>
      if args.length() > 2 {
        Err(CliParseError::UnknownOption(args[2]))
      } else {
        Ok(McpxCommand::Daemon({ mode: DaemonMode::Stop }))
      }
    Some(other) => Err(CliParseError::UnknownOption(other))
  }
}

///|
fn target_server_url(target : String) -> (String, String?) {
  if is_direct_mcp_url(target) {
    ("remote", Some(target))
  } else {
    (target, None)
  }
}

///|
fn is_direct_mcp_url(target : String) -> Bool {
  target.has_prefix("http://") || target.has_prefix("https://")
}
