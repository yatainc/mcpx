///|
test "mcpx runtime: call arguments can come from stdin when JSON arg omitted" {
  let command : CallCommand = {
    server: "github",
    url: None,
    tool: "search",
    arguments_json: None,
  }
  json_inspect(
    resolve_call_arguments(command, stdin_json=Some("{\"q\":\"stdin\"}")).unwrap(),
    content={ "q": "stdin" },
  )
  let command : CallCommand = {
    ..command,
    arguments_json: Some("{\"q\":\"argv\"}"),
  }
  json_inspect(
    resolve_call_arguments(command, stdin_json=Some("{\"q\":\"stdin\"}")).unwrap(),
    content={ "q": "argv" },
  )
}

///|
test "tools call arguments: defaults to object, preserves JSON values and rejects malformed input" {
  let command : CallCommand = {
    server: "github",
    url: None,
    tool: "search",
    arguments_json: None,
  }
  json_inspect(resolve_call_arguments(command).unwrap(), content={})
  json_inspect(
    resolve_call_arguments(command, stdin_json=Some("  \n  ")).unwrap(),
    content={},
  )
  json_inspect(
    resolve_call_arguments(command, stdin_json=Some("[1,true]")).unwrap(),
    content=[1, true],
  )
  @debug.debug_inspect(
    resolve_call_arguments(command, stdin_json=Some("not json")),
    content="Err(\"invalid JSON arguments\")",
  )
}
