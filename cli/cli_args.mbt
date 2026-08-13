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
    None => Ok(Help)
    Some("--help") =>
      if args.length() > 1 {
        Err(UnknownOption(args[1]))
      } else {
        Ok(Help)
      }
    Some("--version") =>
      if args.length() > 1 {
        Err(UnknownOption(args[1]))
      } else {
        Ok(Version)
      }
    Some("call") => parse_call_command(args)
    Some("info") => parse_info_command(args)
    Some("search") => parse_search_command(args)
    Some("auth") => parse_auth_command(args)
    Some("daemon") => parse_daemon_command(args)
    Some(command) => Err(UnknownCommand(command))
  }
}

///|
fn parse_call_command(
  args : Array[String],
) -> Result[McpxCommand, CliParseError] {
  match (args.get(1), args.get(2)) {
    (None, _) => Ok(CallHelp)
    (Some("--url"), _) => Err(InvalidTarget("--url"))
    (_, None) => Err(MissingArgument("tool"))
    (Some(target), Some(tool)) =>
      if args.length() > 4 {
        Err(UnknownOption(args[4]))
      } else {
        let (server, url) = target_server_url(target)
        Ok(Call({ server, url, tool, arguments_json: args.get(3) }))
      }
  }
}

///|
fn parse_info_command(
  args : Array[String],
) -> Result[McpxCommand, CliParseError] {
  match args.get(1) {
    None => Ok(Info({ server: None, url: None, tool: None }))
    Some("--url") => Err(InvalidTarget("--url"))
    Some(target) =>
      if args.length() > 3 {
        Err(UnknownOption(args[3]))
      } else {
        let (server, url) = target_server_url(target)
        Ok(Info({ server: Some(server), url, tool: args.get(2) }))
      }
  }
}

///|
fn parse_search_command(
  args : Array[String],
) -> Result[McpxCommand, CliParseError] {
  match args.get(1) {
    None => Ok(SearchHelp)
    Some(pattern) =>
      if args.length() > 2 {
        Err(UnknownOption(args[2]))
      } else {
        Ok(Search({ pattern, }))
      }
  }
}

///|
fn parse_auth_command(
  args : Array[String],
) -> Result[McpxCommand, CliParseError] {
  match args.get(1) {
    None => Ok(AuthHelp)
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
              None => return Err(MissingArgument("code"))
            }
          "--state" =>
            match args.get(i + 1) {
              Some(value) => {
                state = Some(value)
                continue i + 2
              }
              None => return Err(MissingArgument("state"))
            }
          "--iss" =>
            match args.get(i + 1) {
              Some(value) => {
                issuer = Some(value)
                continue i + 2
              }
              None => return Err(MissingArgument("iss"))
            }
          option => return Err(UnknownOption(option))
        }
        continue i + 1
      }
      Ok(Auth({ server, no_browser, json_output, code, state, issuer }))
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
        Err(UnknownOption(args[2]))
      } else {
        Ok(Daemon({ mode: Help }))
      }
    Some("status") =>
      if args.length() > 2 {
        Err(UnknownOption(args[2]))
      } else {
        Ok(Daemon({ mode: Status }))
      }
    Some("stop") =>
      if args.length() > 2 {
        Err(UnknownOption(args[2]))
      } else {
        Ok(Daemon({ mode: Stop }))
      }
    Some(other) => Err(UnknownOption(other))
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
