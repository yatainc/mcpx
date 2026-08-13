///|
test "mcpx info: displays JSON Schema 2020-12 constructs without loss" {
  let schema = Json::object({
    "$schema": Json::string("https://json-schema.org/draft/2020-12/schema"),
    "$defs": Json::object({
      "filter": Json::object({
        "type": Json::string("object"),
        "unevaluatedProperties": Json::boolean(false),
      }),
    }),
    "type": Json::string("object"),
    "properties": Json::object({
      "coordinates": Json::object({
        "type": Json::string("array"),
        "prefixItems": Json::array([
          Json::object({ "type": Json::string("number") }),
          Json::object({ "type": Json::string("number") }),
        ]),
      }),
    }),
  })
  let output = tool_schema_result(
    "maps",
    @mcp_client.mcp_tool_info(name="locate", input_schema=schema),
  )
  inspect(output.contains("Input Schema:"), content="true")
  inspect(output.contains("\"$defs\""), content="true")
  inspect(output.contains("\"prefixItems\""), content="true")
  inspect(output.contains("\"unevaluatedProperties\": false"), content="true")
}

///|
test "mcpx info: displays composition input and primitive output schemas" {
  let output = tool_schema_result(
    "lookup",
    @mcp_client.mcp_tool_info(
      name="find",
      input_schema={
        "type": "object",
        "oneOf": [{ "required": ["id"] }, { "required": ["name"] }],
        "if": { "required": ["id"] },
        "then": { "properties": { "id": { "type": "integer" } } },
        "else": { "properties": { "name": { "type": "string" } } },
      },
      output_schema=Some({ "type": "number" }),
    ),
  )
  inspect(output.contains("Input Schema:"), content="true")
  inspect(output.contains("\"oneOf\""), content="true")
  inspect(output.contains("\"if\""), content="true")
  inspect(output.contains("Output Schema:"), content="true")
  inspect(output.contains("\"type\": \"number\""), content="true")
}

///|
test "mcpx info: displays nested JSON Schema constructs without loss" {
  let output = tool_schema_result(
    "lookup",
    @mcp_client.mcp_tool_info(name="find", input_schema={
      "type": "object",
      "properties": {
        "value": { "oneOf": [{ "type": "string" }, { "type": "integer" }] },
      },
    }),
  )
  inspect(output.contains("Input Schema:"), content="true")
  inspect(output.contains("\"oneOf\""), content="true")
}

///|
test "mcpx info: keeps concise output for basic schemas" {
  let output = tool_schema_result(
    "search",
    @mcp_client.mcp_tool_info(name="find", input_schema={
      "type": "object",
      "properties": { "query": { "type": "string" } },
      "required": ["query"],
    }),
  )
  inspect(output.contains("query  string required"), content="true")
  inspect(output.contains("Input Schema:"), content="false")
}
