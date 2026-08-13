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
test "HTTP tool headers extract and encode primitive argument values" {
  let bindings = inspect_mcp_tool_header_bindings(
    @json.parse(
      (
        #|{"type":"object","properties":{"region":{"type":"string","x-mcp-header":"Region"},"options":{"type":"object","properties":{"dryRun":{"type":"boolean","x-mcp-header":"Dry-Run"},"limit":{"type":"integer","x-mcp-header":"Limit"}}}}}
      ),
    ),
  ).unwrap()
  let headers = build_mcp_tool_parameter_headers(
    bindings,
    @json.parse(
      (
        #|{"region":"日本","options":{"dryRun":true,"limit":42}}
      ),
    ),
  ).unwrap()
  inspect(headers["Mcp-Param-Region"], content="=?base64?5pel5pys?=")
  inspect(headers["Mcp-Param-Dry-Run"], content="true")
  inspect(headers["Mcp-Param-Limit"], content="42")
}

///|
test "HTTP tool headers omit missing values and reject type mismatches" {
  let bindings = inspect_mcp_tool_header_bindings(
    @json.parse(
      (
        #|{"type":"object","properties":{"region":{"type":"string","x-mcp-header":"Region"}}}
      ),
    ),
  ).unwrap()
  inspect(
    build_mcp_tool_parameter_headers(bindings, Json::empty_object())
    .unwrap()
    .is_empty(),
    content="true",
  )
  inspect(
    build_mcp_tool_parameter_headers(bindings, { "region": 42 }) is Err(_),
    content="true",
  )
}

///|
test "HTTP tool headers canonicalize integer values" {
  let bindings = inspect_mcp_tool_header_bindings(
    Json::object({
      "type": Json::string("object"),
      "properties": Json::object({
        "n": Json::object({
          "type": Json::string("integer"),
          "x-mcp-header": Json::string("N"),
        }),
      }),
    }),
  ).unwrap()
  let headers = build_mcp_tool_parameter_headers(
    bindings,
    Json::object({ "n": Json::number(42.0, repr="4.2e1") }),
  ).unwrap()
  inspect(headers["Mcp-Param-N"], content="42")
}

///|
test "HTTP tool headers reject annotations in malformed properties" {
  let schema = Json::object({
    "type": Json::string("object"),
    "properties": Json::array([
      Json::object({
        "type": Json::string("string"),
        "x-mcp-header": Json::string("Hidden"),
      }),
    ]),
  })
  inspect(inspect_mcp_tool_header_bindings(schema) is Err(_), content="true")
}

///|
test "HTTP tool header schema inspection has resource bounds" {
  let mut schema : Json = Json::object({
    "type": Json::string("string"),
    "x-mcp-header": Json::string("Deep"),
  })
  for i in 0..<80 {
    let properties : Map[String, Json] = Map([])
    properties["level" + i.to_string()] = schema
    schema = Json::object({
      "type": Json::string("object"),
      "properties": Json::object(properties),
    })
  }
  inspect(inspect_mcp_tool_header_bindings(schema) is Err(_), content="true")

  let properties : Map[String, Json] = Map([])
  for i in 0..<12000 {
    properties["p" + i.to_string()] = Json::object({
      "type": Json::string("string"),
    })
  }
  inspect(
    inspect_mcp_tool_header_bindings(
      Json::object({
        "type": Json::string("object"),
        "properties": Json::object(properties),
      }),
    )
    is Err(_),
    content="true",
  )
}

///|
test "HTTP tool headers reject non-object input schemas" {
  inspect(
    inspect_mcp_tool_header_bindings(Json::array([])) is Err(_),
    content="true",
  )
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
