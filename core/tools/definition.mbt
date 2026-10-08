///|
pub struct McpToolInfo {
  name : String
  description : String?
  input_schema : Json
  output_schema : Json?
} derive(Debug)

///|
pub extend McpToolInfo with Debug::{to_repr}

///|
pub fn mcp_tool_info(
  name~ : String,
  description? : String? = None,
  input_schema~ : Json,
  output_schema? : Json? = None,
) -> McpToolInfo {
  { name, description, input_schema, output_schema, }
}

///|
pub extend McpToolInfo with ToJson::{to_json}

///|
pub impl ToJson for McpToolInfo with fn to_json(self) {
  let obj : Map[String, Json] = { "name": self.name.to_json() }
  match self.description {
    Some(value) => obj["description"] = value.to_json()
    None => ()
  }
  obj["inputSchema"] = self.input_schema
  match self.output_schema {
    Some(value) => obj["outputSchema"] = value
    None => ()
  }
  Json::object(obj)
}

///|
fn decode_tool(json : Json) -> McpToolInfo raise @protocol.McpProtocolError {
  let obj = match json {
    Object(value) => value
    _ => raise InvalidResponse("tool must be object")
  }
  let name = match obj.get("name") {
    Some(String(value)) => value
    _ => raise InvalidResponse("tool.name must be string")
  }
  let description = match obj.get("description") {
    Some(String(value)) => Some(value)
    Some(_) => raise InvalidResponse("tool.description must be string")
    None => None
  }
  let input_schema = match obj.get("inputSchema") {
    Some(Object(_) as value) => value
    _ => raise InvalidResponse("tool.inputSchema must be object")
  }
  let output_schema = match obj.get("outputSchema") {
    Some(Object(_) as value) => Some(value)
    Some(_) => raise InvalidResponse("tool.outputSchema must be object")
    None => None
  }
  { name, description, input_schema, output_schema, }
}
