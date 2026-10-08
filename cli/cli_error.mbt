///|
fn format_mcpx_parse_error(error : CliParseError) -> String {
  match error {
    MissingArgument(name) => "missing argument: " + name
    InvalidTarget(target) =>
      "invalid target: " + target + " (expected server or url)"
    UnknownOption(option) => "unknown option: " + option
    UnknownCommand(command) => "unknown command: " + command
  }
}
