///|
fn assert_invalid_schema(schema : Json) -> Unit raise {
  try header_bindings(schema) catch {
    InvalidResponse(_) => ()
    _ => fail("expected invalid header schema")
  } noraise {
    _ => fail("expected error")
  }
}

///|
test "HTTP tool headers accept reachable primitive annotations" {
  let bindings = header_bindings({
    "type": "object",
    "properties": {
      "region": { "type": "string", "x-mcp-header": "Region" },
      "options": {
        "type": "object",
        "properties": {
          "dryRun": { "type": "boolean", "x-mcp-header": "Dry-Run" },
          "limit": { "type": "integer", "x-mcp-header": "Limit" },
        },
      },
    },
  })
  inspect(bindings.length(), content="3")
  inspect(bindings[0].name, content="Region")
  inspect(bindings[0].path.join("."), content="region")
  inspect(bindings[1].path.join("."), content="options.dryRun")
  inspect(bindings[2].path.join("."), content="options.limit")
}

///|
test "HTTP tool headers reject invalid annotations" {
  let schemas : Array[Json] = [
    {
      "type": "object",
      "properties": { "x": { "type": "string", "x-mcp-header": "" } },
    },
    {
      "type": "object",
      "properties": { "x": { "type": "string", "x-mcp-header": "Bad Name" } },
    },
    {
      "type": "object",
      "properties": { "x": { "type": "number", "x-mcp-header": "Number" } },
    },
    {
      "type": "object",
      "properties": { "x": { "type": "object", "x-mcp-header": "Object" } },
    },
    { "type": "array", "items": { "type": "string", "x-mcp-header": "Item" } },
    { "oneOf": [{ "type": "string", "x-mcp-header": "Choice" }] },
    { "$defs": { "x": { "type": "string", "x-mcp-header": "Ref" } } },
  ]
  schemas.each(assert_invalid_schema)
}

///|
test "Tool header values leave HTTP encoding to the transport" {
  let bindings = header_bindings({
    "type": "object",
    "properties": {
      "region": { "type": "string", "x-mcp-header": "Region" },
      "options": {
        "type": "object",
        "properties": {
          "dryRun": { "type": "boolean", "x-mcp-header": "Dry-Run" },
          "limit": { "type": "integer", "x-mcp-header": "Limit" },
        },
      },
    },
  })
  let values = parameter_values(bindings, {
    "region": "日本",
    "options": { "dryRun": true, "limit": 42 },
  })
  inspect(values["Region"], content="日本")
  inspect(values["Dry-Run"], content="true")
  inspect(values["Limit"], content="42")
}

///|
test "HTTP tool headers omit missing values and reject type mismatches" {
  let bindings = header_bindings({
    "type": "object",
    "properties": { "region": { "type": "string", "x-mcp-header": "Region" } },
  })
  inspect(parameter_values(bindings, {}).is_empty(), content="true")
  try parameter_values(bindings, { "region": 42 }) catch {
    InvalidResponse(message) =>
      inspect(message, content="tool header argument type mismatch")
    _ => fail("expected type mismatch")
  } noraise {
    _ => fail("expected error")
  }
}

///|
test "HTTP tool headers canonicalize integer values" {
  let bindings = header_bindings({
    "type": "object",
    "properties": { "n": { "type": "integer", "x-mcp-header": "N" } },
  })
  let values = parameter_values(bindings, {
    "n": Json::number(42.0, repr="4.2e1"),
  })
  inspect(values["N"], content="42")
}

///|
test "HTTP tool headers reject annotations in malformed properties" {
  assert_invalid_schema({
    "type": "object",
    "properties": [{ "type": "string", "x-mcp-header": "Hidden" }],
  })
}

///|
test "HTTP tool header schema inspection has resource bounds" {
  let mut schema : Json = { "type": "string", "x-mcp-header": "Deep" }
  for i in 0..<80 {
    let properties = Map([])
    properties["level" + i.to_string()] = schema
    schema = { "type": "object", "properties": properties.to_json() }
  }
  assert_invalid_schema(schema)
  let properties = Map([])
  for i in 0..<12000 {
    properties["p" + i.to_string()] = Json::object({ "type": "string" })
  }
  assert_invalid_schema({ "type": "object", "properties": properties.to_json() })
}

///|
test "HTTP tool headers reject non-object input schemas" {
  assert_invalid_schema([])
}

///|
test "HTTP tool headers reject case-insensitive duplicates" {
  assert_invalid_schema({
    "type": "object",
    "properties": {
      "a": { "type": "string", "x-mcp-header": "Region" },
      "b": { "type": "string", "x-mcp-header": "region" },
    },
  })
}
