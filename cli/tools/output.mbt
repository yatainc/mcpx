///|
fn call_result(result : Json) -> String {
  let parts = match result {
    { "content": Array(items), .. } =>
      items.filter_map(item => {
        match item {
          { "type": String("text"), "text": String(text), .. } => Some(text)
          _ => None
        }
      })
    _ => []
  }
  if parts.is_empty() {
    "Result:\n" + result.stringify()
  } else {
    parts.join("\n\n")
  }
}

///|
fn info_tools_result(
  server_name : String,
  tools : Array[@core_tools.McpToolInfo],
  tool : String?,
  filter_server~ : @config.McpServerConfig?,
) -> String {
  let tools = match filter_server {
    None => tools
    Some(server) => @config.filter_tools(server, tools, tool => tool.name)
  }
  match tool {
    None => tools_text_result(tools)
    Some(name) =>
      match tools.search_by(tool => tool.name == name) {
        None => error_result("tool not found: " + name)
        Some(index) => tool_schema_result(server_name, tools[index])
      }
  }
}

///|
fn tools_text_result(tools : Array[@core_tools.McpToolInfo]) -> String {
  if tools.is_empty() {
    return "Tools\n  (none)"
  }
  let lines = ["Tools"]
  for tool in tools {
    lines.push(
      "  " +
      tool.name +
      "(" +
      schema_required_args(tool.input_schema).join(", ") +
      ")",
    )
    match first_description_line(tool.description) {
      Some(summary) => lines.push("    " + summary)
      None => ()
    }
  }
  lines.join("\n")
}

///|
fn tool_schema_result(
  server_name : String,
  tool : @core_tools.McpToolInfo,
) -> String {
  let lines = ["Tool: " + server_name + "/" + tool.name]
  match first_description_line(tool.description) {
    Some(summary) => {
      lines.push("")
      lines.push(summary)
    }
    None => ()
  }
  lines.push("")
  lines.push("Arguments:")
  let properties = match tool.input_schema {
    { "properties": Object(properties), .. } => properties
    _ => Map([])
  }
  if properties.is_empty() {
    lines.push("  (none)")
  } else {
    let required = schema_required_args(tool.input_schema)
    for name, value in properties {
      let marker = if required.contains(name) { " required" } else { "" }
      let type_text = match value {
        { "type": String(value), .. } => value
        _ => ""
      }
      lines.push(
        "  " +
        name +
        (if type_text.is_empty() { "" } else { "  " + type_text }) +
        marker,
      )
      match value {
        { "description": String(description), .. } =>
          match first_description_line(Some(description)) {
            Some(description) => lines.push("    " + description)
            None => ()
          }
        _ => ()
      }
    }
  }
  if schema_requires_complete_display(tool.input_schema, depth=0) {
    lines.push("")
    lines.push("Input Schema:")
    lines.push(tool.input_schema.stringify(indent=2))
  }
  match tool.output_schema {
    Some(schema) => {
      lines.push("")
      lines.push("Output Schema:")
      lines.push(schema.stringify(indent=2))
    }
    None => ()
  }
  lines.join("\n")
}

///|
fn first_description_line(description : String?) -> String? {
  match description {
    None => None
    Some(text) => {
      for line in text.split("\n") {
        let line = line.trim().to_owned()
        if !line.is_empty() {
          return Some(line)
        }
      }
      None
    }
  }
}

///|
fn schema_required_args(schema : Json) -> Array[String] {
  match schema {
    { "required": Array(values), .. } =>
      values.filter_map(value => {
        match value {
          String(name) => Some(name)
          _ => None
        }
      })
    _ => []
  }
}

///|
fn schema_requires_complete_display(schema : Json, depth~ : Int) -> Bool {
  if depth > 64 {
    return true
  }
  let obj = match schema {
    Object(value) => value
    _ => return true
  }
  for key, value in obj {
    if key == "properties" {
      match value {
        Object(properties) =>
          for _, property_schema in properties {
            if schema_requires_complete_display(
                property_schema,
                depth=depth + 1,
              ) {
              return true
            }
          }
        _ => return true
      }
    } else if key != "type" &&
      key != "required" &&
      key != "description" &&
      key != "title" {
      return true
    }
  }
  false
}
