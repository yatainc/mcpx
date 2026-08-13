///|
test "cli error: formats unknown command" {
  inspect(
    format_mcpx_parse_error(UnknownCommand("list")),
    content="unknown command: list",
  )
}

///|
test "cli error: formats invalid target" {
  inspect(
    format_mcpx_parse_error(InvalidTarget("github")),
    content="invalid target: github (expected server or url)",
  )
}
