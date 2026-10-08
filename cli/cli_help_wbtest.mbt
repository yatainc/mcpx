///|
async test "cli output: help text is human-readable" {
  let help = execute_mcpx([], home="/tmp/mcpx-help-test/home")
  inspect(help.contains("mcpx — execute MCP tools via CLI"), content="true")
  inspect(help.contains("mcpx info <server|url> [tool]"), content="true")
  inspect(help.contains("mcpx search <pattern>"), content="true")
}

///|
async test "cli output: version text" {
  inspect(
    execute_mcpx(["--version"], home="/tmp/mcpx-help-test/home"),
    content="mcpx 0.2.0",
  )
}

///|
async test "cli output: command-specific help text" {
  inspect(
    execute_mcpx(["call"], home="/tmp/mcpx-help-test/home"),
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
    execute_mcpx(["search"], home="/tmp/mcpx-help-test/home"),
    content=(
      #|mcpx search
      #|
      #|Usage:
      #|  mcpx search <pattern>
    ),
  )
  inspect(
    execute_mcpx(["auth"], home="/tmp/mcpx-help-test/home"),
    content=(
      #|mcpx auth
      #|
      #|Usage:
      #|  mcpx auth <server> [--no-browser] [--json]
      #|  mcpx auth <server> --code <code> --state <state> [--iss <issuer>]
    ),
  )
  inspect(
    execute_mcpx(["daemon"], home="/tmp/mcpx-help-test/home"),
    content=(
      #|mcpx daemon
      #|
      #|Usage:
      #|  mcpx daemon
      #|  mcpx daemon <status|stop>
    ),
  )
}
