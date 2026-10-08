///|
priv enum HeaderValueType {
  StringValue
  IntegerValue
  BooleanValue
}

///|
priv struct HeaderBinding {
  name : String
  path : Array[String]
  value_type : HeaderValueType
}

///|
fn header_bindings(
  schema : Json,
) -> Array[HeaderBinding] raise @protocol.McpProtocolError {
  match schema {
    Object(_) => ()
    _ => raise InvalidResponse("tool inputSchema must be an object")
  }
  validate_header_schema_bounds(schema, depth=0, visited=Ref(0))
  let bindings = []
  inspect_header_schema(schema, [], bindings, HashSet([]))
  bindings
}

///|
fn validate_header_schema_bounds(
  value : Json,
  depth~ : Int,
  visited~ : Ref[Int],
) -> Unit raise @protocol.McpProtocolError {
  if depth > 64 {
    raise InvalidResponse("tool schema exceeds maximum nesting depth")
  }
  visited.val += 1
  if visited.val > 10000 {
    raise InvalidResponse("tool schema exceeds maximum node count")
  }
  match value {
    Object(obj) =>
      for _, child in obj {
        validate_header_schema_bounds(child, depth=depth + 1, visited~)
      }
    Array(items) =>
      for child in items {
        validate_header_schema_bounds(child, depth=depth + 1, visited~)
      }
    _ => ()
  }
}

///|
fn inspect_header_schema(
  schema : Json,
  path : Array[String],
  bindings : Array[HeaderBinding],
  names : @hashset.HashSet[String],
) -> Unit raise @protocol.McpProtocolError {
  let obj = match schema {
    Object(value) => value
    _ => return
  }
  match obj.get("x-mcp-header") {
    Some(String(name)) => {
      if path.is_empty() {
        raise InvalidResponse("x-mcp-header is not statically reachable")
      }
      if !is_header_token(name) {
        raise InvalidResponse("x-mcp-header is not a valid HTTP field token")
      }
      if !names.add_and_check(name.to_lower()) {
        raise InvalidResponse("duplicate x-mcp-header")
      }
      let value_type = match obj.get("type") {
        Some(String("string")) => HeaderValueType::StringValue
        Some(String("integer")) => IntegerValue
        Some(String("boolean")) => BooleanValue
        _ =>
          raise InvalidResponse(
            "x-mcp-header requires string, integer, or boolean",
          )
      }
      bindings.push({ name, path, value_type })
    }
    Some(_) => raise InvalidResponse("x-mcp-header must be a string")
    None => ()
  }
  for key, value in obj {
    if key == "properties" {
      match value {
        Object(properties) =>
          for property_name, property_schema in properties {
            let child_path = path.copy()
            child_path.push(property_name)
            inspect_header_schema(property_schema, child_path, bindings, names)
          }
        _ =>
          if contains_header_annotation(value) {
            raise InvalidResponse("x-mcp-header is not statically reachable")
          }
      }
    } else if key != "x-mcp-header" && contains_header_annotation(value) {
      raise InvalidResponse("x-mcp-header is not statically reachable")
    }
  }
}

///|
fn parameter_values(
  bindings : Array[HeaderBinding],
  arguments : Json,
) -> Map[String, String] raise @protocol.McpProtocolError {
  let values = Map([])
  for binding in bindings {
    match json_value_at_path(arguments, binding.path) {
      None => ()
      Some(value) => {
        let text = match (binding.value_type, value) {
          (StringValue, String(text)) => text
          (BooleanValue, True) => "true"
          (BooleanValue, False) => "false"
          (IntegerValue, Number(value, ..)) if value.trunc() == value &&
            value >= -9007199254740991.0 &&
            value <= 9007199254740991.0 => value.to_int64().to_string()
          _ => raise InvalidResponse("tool header argument type mismatch")
        }
        values[binding.name] = text
      }
    }
  }
  values
}

///|
fn json_value_at_path(value : Json, path : Array[String]) -> Json? {
  let mut current = value
  for segment in path {
    match current {
      Object(obj) =>
        match obj.get(segment) {
          Some(next) => current = next
          None => return None
        }
      _ => return None
    }
  }
  Some(current)
}

///|
fn contains_header_annotation(value : Json) -> Bool {
  match value {
    Object(obj) =>
      obj.contains("x-mcp-header") ||
      obj.values().any(contains_header_annotation)
    Array(items) => items.any(contains_header_annotation)
    _ => false
  }
}

///|
fn is_header_token(value : String) -> Bool {
  !value.is_empty() &&
  value
  .iter()
  .all(char => {
    let code = char.to_int()
    (code >= 0x30 && code <= 0x39) ||
    (code >= 0x41 && code <= 0x5a) ||
    (code >= 0x61 && code <= 0x7a) ||
    "!#$%&'*+-.^_`|~".contains(char.to_string())
  })
}
