///|
test "cli render: help text is human-readable" {
  match parse_mcpx_args([]) {
    Ok(command) => {
      let help = render_mcpx_command(command)
      inspect(
        help.contains("mcpx — execute MCP tools via CLI"),
        content="true",
      )
      inspect(help.contains("mcpx info <server|url> [tool]"), content="true")
      inspect(help.contains("mcpx search <pattern>"), content="true")
    }
    Err(error) => @debug.debug_inspect(error, content="UNREACHABLE")
  }
}

///|
test "cli render: version text" {
  match parse_mcpx_args(["--version"]) {
    Ok(command) => inspect(render_mcpx_command(command), content="mcpx 0.1.4")
    Err(error) => @debug.debug_inspect(error, content="UNREACHABLE")
  }
}

///|
test "cli render: command-specific help text" {
  let call = parse_mcpx_args(["call"]).unwrap()
  let search = parse_mcpx_args(["search"]).unwrap()
  let auth = parse_mcpx_args(["auth"]).unwrap()
  let daemon = parse_mcpx_args(["daemon"]).unwrap()
  inspect(
    render_mcpx_command(call),
    content=(
      #|mcpx call
      #|
      #|Usage:
      #|  mcpx call <server|url> <tool> [arguments-json]
      #|
      #|Examples:
      #|  mcpx call github search '{"q":"moonbit"}'
      #|  echo '{"q":"moonbit"}' | mcpx call github search
    ),
  )
  inspect(
    render_mcpx_command(search),
    content=(
      #|mcpx search
      #|
      #|Usage:
      #|  mcpx search <pattern>
    ),
  )
  inspect(
    render_mcpx_command(auth),
    content=(
      #|mcpx auth
      #|
      #|Usage:
      #|  mcpx auth <server> [--no-browser] [--json]
      #|  mcpx auth <server> --code <code> --state <state> [--iss <issuer>]
    ),
  )
  inspect(
    render_mcpx_command(daemon),
    content=(
      #|mcpx daemon
      #|
      #|Usage:
      #|  mcpx daemon
      #|  mcpx daemon <status|stop>
    ),
  )
}

///|
test "cli render: auth command stays explicit and headless-aware" {
  match parse_mcpx_args(["auth", "github", "--no-browser", "--json"]) {
    Ok(command) =>
      inspect(
        render_mcpx_command(command),
        content=(
          #|{"action":"auth","server":"github","noBrowser":true,"json":true}
        ),
      )
    Err(error) => @debug.debug_inspect(error, content="UNREACHABLE")
  }
}

///|
test "cli render: auth completion hides code details in command plan shape" {
  match
    parse_mcpx_args(["auth", "github", "--code", "code-1", "--state", "state-1"]) {
    Ok(command) =>
      inspect(
        render_mcpx_command(command),
        content=(
          #|{"action":"auth","server":"github","noBrowser":false,"json":false,"codeProvided":true,"stateProvided":true}
        ),
      )
    Err(error) => @debug.debug_inspect(error, content="UNREACHABLE")
  }
}

///|
test "cli render: info command is JSON plan for native runner" {
  match parse_mcpx_args(["info", "github", "search"]) {
    Ok(command) =>
      inspect(
        render_mcpx_command(command),
        content=(
          #|{"action":"info","server":"github","tool":"search"}
        ),
      )
    Err(error) => @debug.debug_inspect(error, content="UNREACHABLE")
  }
}

///|
test "cli render: direct URL call includes URL and tool" {
  match parse_mcpx_args(["call", "http://localhost:3000/mcp", "search"]) {
    Ok(command) =>
      inspect(
        render_mcpx_command(command),
        content=(
          #|{"action":"call","server":"remote","url":"http://localhost:3000/mcp","tool":"search"}
        ),
      )
    Err(error) => @debug.debug_inspect(error, content="UNREACHABLE")
  }
}

///|
test "cli render: direct URL info includes URL" {
  match parse_mcpx_args(["info", "http://localhost:3000/mcp"]) {
    Ok(command) =>
      inspect(
        render_mcpx_command(command),
        content=(
          #|{"action":"info","server":"remote","url":"http://localhost:3000/mcp"}
        ),
      )
    Err(error) => @debug.debug_inspect(error, content="UNREACHABLE")
  }
}

///|
test "cli render: search command is JSON plan for native runner" {
  match parse_mcpx_args(["search", "search"]) {
    Ok(command) =>
      inspect(
        render_mcpx_command(command),
        content="{\"action\":\"search\",\"pattern\":\"search\"}",
      )
    Err(error) => @debug.debug_inspect(error, content="UNREACHABLE")
  }
}

///|
test "cli render: call command is JSON plan for native runner" {
  match parse_mcpx_args(["call", "github", "search", "{\"q\":\"moonbit\"}"]) {
    Ok(command) =>
      inspect(
        render_mcpx_command(command),
        content=(
          #|{"action":"call","server":"github","tool":"search","arguments":"{\"q\":\"moonbit\"}"}
        ),
      )
    Err(error) => @debug.debug_inspect(error, content="UNREACHABLE")
  }
}

///|
test "cli render: daemon command" {
  match parse_mcpx_args(["daemon", "stop"]) {
    Ok(command) =>
      inspect(
        render_mcpx_command(command),
        content="{\"action\":\"daemon\",\"mode\":\"stop\"}",
      )
    Err(_) => inspect("unexpected", content="unexpected")
  }
}
