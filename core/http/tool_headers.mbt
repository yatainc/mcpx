///|
priv suberror McpToolHeaderError {
  McpToolHeaderError(String)
} derive(Debug)

///|
pub(all) enum McpHttpHeaderValueType {
  StringValue
  IntegerValue
  BooleanValue
} derive(Debug, Eq)

///|
pub(all) struct McpToolHeaderBinding {
  header_name : String
  property_path : Array[String]
  value_type : McpHttpHeaderValueType
} derive(Debug)

///|
pub fn inspect_mcp_tool_header_bindings(
  schema : Json,
) -> Result[Array[McpToolHeaderBinding], String] {
  let bindings = []
  let names : Map[String, Unit] = Map([])
  inspect_header_schema_node(schema, [], true, bindings, names) catch {
    McpToolHeaderError(error) => return Err(error)
  }
  Ok(bindings)
}

///|
fn inspect_header_schema_node(
  schema : Json,
  path : Array[String],
  reachable : Bool,
  bindings : Array[McpToolHeaderBinding],
  names : Map[String, Unit],
) -> Unit raise McpToolHeaderError {
  let obj = match schema {
    Object(value) => value
    _ => return
  }
  match obj.get("x-mcp-header") {
    Some(String(name)) => {
      if !reachable || path.is_empty() {
        raise McpToolHeaderError("x-mcp-header is not statically reachable")
      }
      if !is_mcp_header_token(name) {
        raise McpToolHeaderError("x-mcp-header is not a valid HTTP field token")
      }
      let normalized = name.to_lower()
      if names.contains(normalized) {
        raise McpToolHeaderError("duplicate x-mcp-header")
      }
      let value_type = match obj.get("type") {
        Some(String("string")) => McpHttpHeaderValueType::StringValue
        Some(String("integer")) => McpHttpHeaderValueType::IntegerValue
        Some(String("boolean")) => McpHttpHeaderValueType::BooleanValue
        _ =>
          raise McpToolHeaderError(
            "x-mcp-header requires string, integer, or boolean",
          )
      }
      names[normalized] = ()
      bindings.push({ header_name: name, property_path: path, value_type })
    }
    Some(_) => raise McpToolHeaderError("x-mcp-header must be a string")
    None => ()
  }
  for key, value in obj {
    if key == "properties" {
      match value {
        Object(properties) if reachable =>
          for property_name, property_schema in properties {
            let child_path = path.copy()
            child_path.push(property_name)
            inspect_header_schema_node(
              property_schema, child_path, true, bindings, names,
            )
          }
        _ => ()
      }
    } else if key != "x-mcp-header" && contains_mcp_header_annotation(value) {
      raise McpToolHeaderError("x-mcp-header is not statically reachable")
    }
  }
}

///|
pub fn build_mcp_tool_parameter_headers(
  bindings : Array[McpToolHeaderBinding],
  arguments : Json,
) -> Result[Map[String, String], String] {
  let headers : Map[String, String] = Map([])
  for binding in bindings {
    match json_value_at_path(arguments, binding.property_path) {
      None => ()
      Some(value) => {
        let text = match (binding.value_type, value) {
          (McpHttpHeaderValueType::StringValue, String(text)) => text
          (McpHttpHeaderValueType::BooleanValue, True) => "true"
          (McpHttpHeaderValueType::BooleanValue, False) => "false"
          (McpHttpHeaderValueType::IntegerValue, Number(value, repr~)) if value.trunc() ==
            value &&
            value >= -9007199254740991.0 &&
            value <= 9007199254740991.0 =>
            repr.unwrap_or(value.to_int64().to_string())
          _ => return Err("tool header argument type mismatch")
        }
        headers["Mcp-Param-" + binding.header_name] = encode_mcp_http_header_value(
          text,
        )
      }
    }
  }
  Ok(headers)
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
fn contains_mcp_header_annotation(value : Json) -> Bool {
  match value {
    Object(obj) => {
      if obj.contains("x-mcp-header") {
        return true
      }
      for _, child in obj {
        if contains_mcp_header_annotation(child) {
          return true
        }
      }
      false
    }
    Array(items) => items.any(contains_mcp_header_annotation)
    _ => false
  }
}

///|
fn is_mcp_header_token(value : String) -> Bool {
  if value.is_empty() {
    return false
  }
  for char in value {
    let code = char.to_int()
    let alpha_numeric = (code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x5a) ||
      (code >= 0x61 && code <= 0x7a)
    let punctuation = char == '!' ||
      char == '#' ||
      char == '$' ||
      char == '%' ||
      char == '&' ||
      char == '\'' ||
      char == '*' ||
      char == '+' ||
      char == '-' ||
      char == '.' ||
      char == '^' ||
      char == '_' ||
      char == '`' ||
      char == '|' ||
      char == '~'
    if !alpha_numeric && !punctuation {
      return false
    }
  }
  true
}
