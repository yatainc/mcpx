///|
fn mcpx_help_text() -> String {
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
fn call_help_text() -> String {
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
fn search_help_text() -> String {
  (
    #|mcpx search
    #|
    #|Usage:
    #|  mcpx search <pattern>
  )
}

///|
fn auth_help_text() -> String {
  (
    #|mcpx auth
    #|
    #|Usage:
    #|  mcpx auth <server> [--no-browser] [--json]
    #|  mcpx auth <server> --code <code> --state <state> [--iss <issuer>]
  )
}

///|
fn daemon_help_text() -> String {
  (
    #|mcpx daemon
    #|
    #|Usage:
    #|  mcpx daemon
    #|  mcpx daemon <status|stop>
  )
}
