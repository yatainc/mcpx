///|
fn parse_retrieval_command(
  args : Array[String],
) -> Result[McpxCommand, CliParseError] {
  let resources = args[0] == "resources"
  if args.length() == 1 || (args.length() == 2 && args[1] == "--help") {
    return Ok(if resources { ResourcesHelp } else { SkillsHelp })
  }
  guard args.get(1) is Some(target) && !target.has_prefix("--") else {
    return Err(MissingArgument("server|url"))
  }
  let mut uri : String? = None
  let mut json_output = false
  let mut verify = false
  for arg in args[2:] {
    match arg {
      "--json" if !json_output => json_output = true
      "--verify" if !resources && !verify => verify = true
      _ if arg.has_prefix("--") => return Err(UnknownOption(arg))
      _ if uri is None => uri = Some(arg)
      _ => return Err(UnknownOption(arg))
    }
  }
  if verify && uri is None {
    return Err(MissingArgument("skill-uri for --verify"))
  }
  let operation = match (resources, uri) {
    (false, None) => @skill_cli.Operation::List
    (false, Some(uri)) => if verify { Verify(uri) } else { Get(uri) }
    (true, Some(uri)) => Read(uri)
    (true, None) => return Err(MissingArgument("uri"))
  }
  Ok(Retrieve({ target, operation, json_output, }))
}
