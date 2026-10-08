///|
test "modern HTTP catalog: retains validated header bindings" {
  let tool = mcp_tool_info(name="search", input_schema={
    "type": "object",
    "properties": { "region": { "type": "string", "x-mcp-header": "Region" } },
  })
  let validated = validate_tool(tool)
  inspect(validated.info.name, content="search")
  let values = parameter_values(validated.bindings, { "region": "eu" })
  inspect(values.get("Region").unwrap(), content="eu")
}

///|
test "modern HTTP catalog: reports rejected annotation schemas" {
  let tool = mcp_tool_info(name="unsafe", input_schema={
    "type": "object",
    "properties": { "value": { "type": "number", "x-mcp-header": "Value" } },
  })
  try validate_tool(tool) catch {
    InvalidResponse(message) =>
      inspect(
        message,
        content="x-mcp-header requires string, integer, or boolean",
      )
    _ => fail("expected rejected tool")
  } noraise {
    _ => fail("expected error")
  }
}
