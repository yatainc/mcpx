///|
test "cli args: no args and --help render help" {
  @debug.debug_inspect(
    [
      parse_mcpx_args([]),
      parse_mcpx_args(["--help"]),
      parse_mcpx_args(["--version"]),
    ],
    content=(
      #|[Ok(Help), Ok(Help), Ok(Version)]
    ),
  )
}

///|
test "cli args: call command is primary" {
  @debug.debug_inspect(
    parse_mcpx_args(["call", "github", "search", "{\"q\":\"moonbit\"}"]),
    content=(
      #|Ok(
      #|  Call(
      #|    {
      #|      server: "github",
      #|      url: None,
      #|      tool: "search",
      #|      arguments_json: Some("{\"q\":\"moonbit\"}"),
      #|    },
      #|  ),
      #|)
    ),
  )
}

///|
test "cli args: bare commands render command help" {
  @debug.debug_inspect(
    [
      parse_mcpx_args(["call"]),
      parse_mcpx_args(["search"]),
      parse_mcpx_args(["auth"]),
      parse_mcpx_args(["daemon"]),
    ],
    content=(
      #|[
      #|  Ok(CallHelp),
      #|  Ok(SearchHelp),
      #|  Ok(AuthHelp),
      #|  Ok(Daemon({ mode: Help })),
      #|]
    ),
  )
}

///|
test "cli args: target shorthand is not public" {
  @debug.debug_inspect(
    parse_mcpx_args(["github/search"]),
    content=(
      #|Err(UnknownCommand("github/search"))
    ),
  )
}

///|
test "cli args: auth is explicit and can be headless json" {
  @debug.debug_inspect(
    parse_mcpx_args(["auth", "github", "--no-browser", "--json"]),
    content=(
      #|Ok(
      #|  Auth(
      #|    {
      #|      server: "github",
      #|      no_browser: true,
      #|      json_output: true,
      #|      code: None,
      #|      state: None,
      #|      issuer: None,
      #|    },
      #|  ),
      #|)
    ),
  )
}

///|
test "cli args: auth can complete no-browser OAuth with code and state" {
  @debug.debug_inspect(
    parse_mcpx_args(["auth", "github", "--code", "code-1", "--state", "state-1"]),
    content=(
      #|Ok(
      #|  Auth(
      #|    {
      #|      server: "github",
      #|      no_browser: false,
      #|      json_output: false,
      #|      code: Some("code-1"),
      #|      state: Some("state-1"),
      #|      issuer: None,
      #|    },
      #|  ),
      #|)
    ),
  )
}

///|
test "cli args: auth completion accepts RFC 9207 issuer" {
  match
    parse_mcpx_args([
      "auth", "github", "--code", "code-1", "--state", "state-1", "--iss", "https://auth.example",
    ]) {
    Ok(McpxCommand::Auth(command)) =>
      inspect(command.issuer.unwrap(), content="https://auth.example")
    _ => fail("expected auth command")
  }
}

///|
test "cli args: info commands inspect configured servers and tools" {
  @debug.debug_inspect(
    [
      parse_mcpx_args(["info"]),
      parse_mcpx_args(["info", "github"]),
      parse_mcpx_args(["info", "github", "search"]),
    ],
    content=(
      #|[
      #|  Ok(Info({ server: None, url: None, tool: None })),
      #|  Ok(Info({ server: Some("github"), url: None, tool: None })),
      #|  Ok(Info({ server: Some("github"), url: None, tool: Some("search") })),
      #|]
    ),
  )
}

///|
test "cli args: call can target a remote URL directly" {
  @debug.debug_inspect(
    parse_mcpx_args([
      "call", "http://localhost:3000/mcp", "search", "{\"q\":\"moonbit\"}",
    ]),
    content=(
      #|Ok(
      #|  Call(
      #|    {
      #|      server: "remote",
      #|      url: Some("http://localhost:3000/mcp"),
      #|      tool: "search",
      #|      arguments_json: Some("{\"q\":\"moonbit\"}"),
      #|    },
      #|  ),
      #|)
    ),
  )
}

///|
test "cli args: info can target a remote URL directly" {
  @debug.debug_inspect(
    parse_mcpx_args(["info", "https://localhost:3000/mcp", "search"]),
    content=(
      #|Ok(
      #|  Info(
      #|    {
      #|      server: Some("remote"),
      #|      url: Some("https://localhost:3000/mcp"),
      #|      tool: Some("search"),
      #|    },
      #|  ),
      #|)
    ),
  )
}

///|
test "cli args: search searches configured servers" {
  @debug.debug_inspect(
    parse_mcpx_args(["search", "issue"]),
    content=(
      #|Ok(Search({ pattern: "issue" }))
    ),
  )
}

///|
test "cli args: removed public commands are rejected" {
  @debug.debug_inspect(
    [
      parse_mcpx_args(["add", "github", "--url", "https://mcp.github.com/mcp"]),
      parse_mcpx_args(["call", "--url", "http://localhost:3000/mcp", "search"]),
      parse_mcpx_args(["list", "github"]),
      parse_mcpx_args(["info", "--url", "http://localhost:3000/mcp"]),
      parse_mcpx_args(["daemon", "start"]),
      parse_mcpx_args(["daemon", "--serve"]),
      parse_mcpx_args(["help"]),
    ],
    content=(
      #|[
      #|  Err(UnknownCommand("add")),
      #|  Err(InvalidTarget("--url")),
      #|  Err(UnknownCommand("list")),
      #|  Err(InvalidTarget("--url")),
      #|  Err(UnknownOption("start")),
      #|  Err(UnknownOption("--serve")),
      #|  Err(UnknownCommand("help")),
      #|]
    ),
  )
}

///|
test "cli args: daemon public subcommands" {
  @debug.debug_inspect(
    [
      parse_mcpx_args(["daemon"]),
      parse_mcpx_args(["daemon", "status"]),
      parse_mcpx_args(["daemon", "stop"]),
    ],
    content=(
      #|[
      #|  Ok(Daemon({ mode: Help })),
      #|  Ok(Daemon({ mode: Status })),
      #|  Ok(Daemon({ mode: Stop })),
      #|]
    ),
  )
}
