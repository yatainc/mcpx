///|
test "modern HTTP catalog: retains validated header bindings" {
  let tool = @protocol.mcp_tool_info(name="search", input_schema={
    "type": "object",
    "properties": { "region": { "type": "string", "x-mcp-header": "Region" } },
  })
  let validated = validate_http_tool(tool).unwrap()
  inspect(validated.info.name, content="search")
  let headers = validated.header_plan.build_headers({ "region": "eu" }).unwrap()
  inspect(headers.get("Mcp-Param-Region").unwrap(), content="eu")
}

///|
test "modern HTTP catalog: reports rejected annotation schemas" {
  let tool = @protocol.mcp_tool_info(name="unsafe", input_schema={
    "type": "object",
    "properties": { "value": { "type": "number", "x-mcp-header": "Value" } },
  })
  match validate_http_tool(tool) {
    Ok(_) => fail("expected rejected tool")
    Err(message) =>
      inspect(
        message,
        content="x-mcp-header requires string, integer, or boolean",
      )
  }
}
