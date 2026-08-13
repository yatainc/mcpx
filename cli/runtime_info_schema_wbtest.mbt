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
  inspect(output.contains("JSON Schema 2020-12:"), content="true")
  inspect(output.contains("\"$defs\""), content="true")
  inspect(output.contains("\"prefixItems\""), content="true")
  inspect(output.contains("\"unevaluatedProperties\": false"), content="true")
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
  inspect(output.contains("JSON Schema 2020-12:"), content="false")
}
