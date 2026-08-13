///|
test "HTTP tool headers accept reachable primitive annotations" {
  let schema = @json.parse(
    (
      #|{"type":"object","properties":{"region":{"type":"string","x-mcp-header":"Region"},"options":{"type":"object","properties":{"dryRun":{"type":"boolean","x-mcp-header":"Dry-Run"},"limit":{"type":"integer","x-mcp-header":"Limit"}}}}}
    ),
  )
  let bindings = inspect_mcp_tool_header_bindings(schema).unwrap()
  inspect(bindings.length(), content="3")
  inspect(bindings[0].header_name, content="Region")
  inspect(bindings[0].property_path.join("."), content="region")
  inspect(bindings[1].property_path.join("."), content="options.dryRun")
  inspect(bindings[2].property_path.join("."), content="options.limit")
}

///|
test "HTTP tool headers reject invalid annotations" {
  let schemas = [
    (
      #|{"type":"object","properties":{"x":{"type":"string","x-mcp-header":""}}}
    ),
    (
      #|{"type":"object","properties":{"x":{"type":"string","x-mcp-header":"Bad Name"}}}
    ),
    (
      #|{"type":"object","properties":{"x":{"type":"number","x-mcp-header":"Number"}}}
    ),
    (
      #|{"type":"object","properties":{"x":{"type":"object","x-mcp-header":"Object"}}}
    ),
    (
      #|{"type":"array","items":{"type":"string","x-mcp-header":"Item"}}
    ),
    (
      #|{"oneOf":[{"type":"string","x-mcp-header":"Choice"}]}
    ),
    (
      #|{"$defs":{"x":{"type":"string","x-mcp-header":"Ref"}}}
    ),
  ]
  for schema in schemas {
    inspect(
      inspect_mcp_tool_header_bindings(@json.parse(schema)) is Err(_),
      content="true",
    )
  }
}

///|
test "HTTP tool headers reject case-insensitive duplicates" {
  let schema = @json.parse(
    (
      #|{"type":"object","properties":{"a":{"type":"string","x-mcp-header":"Region"},"b":{"type":"string","x-mcp-header":"region"}}}
    ),
  )
  inspect(inspect_mcp_tool_header_bindings(schema) is Err(_), content="true")
}
