///|
pub fn call_params(name : String, arguments : Json) -> Map[String, Json] {
  { "name": name.to_json(), "arguments": arguments }
}

///|
// Owns definition selection and the single header-mismatch refresh/retry.
// The transport owns request IDs, RPC decoding, and HTTP header encoding.
pub async fn call(
  fetch_page : async (String?) -> Json,
  execute : async (Map[String, String]) -> Json,
  tool_name~ : String,
  arguments~ : Json,
  tool_definition? : McpToolInfo? = None,
  on_catalog_refresh? : (McpToolListResult) -> Unit = _ => (),
) -> Json {
  let tool = match tool_definition {
    Some(tool) if tool.name == tool_name => validate_tool(tool)
    Some(_) =>
      raise @protocol.InvalidResponse(
        "cached tool definition name does not match: " + tool_name,
      )
    None => {
      let catalog = fetch_catalog(fetch_page)
      on_catalog_refresh(catalog.result)
      match catalog.find_tool(tool_name) {
        Some(value) => value
        None =>
          raise @protocol.InvalidResponse(
            "tool not found in validated tools/list: " + tool_name,
          )
      }
    }
  }
  execute(parameter_values(tool.bindings, arguments)) catch {
    @protocol.HeaderMismatch(_) => {
      let refreshed = fetch_catalog(fetch_page)
      let tool = match refreshed.find_tool(tool_name) {
        Some(value) => value
        None =>
          raise @protocol.InvalidResponse(
            "tool not found after header schema refresh: " + tool_name,
          )
      }
      let result = execute(parameter_values(tool.bindings, arguments))
      on_catalog_refresh(refreshed.result)
      result
    }
    error => raise error
  }
}
