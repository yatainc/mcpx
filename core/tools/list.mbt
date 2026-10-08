///|
pub const MCP_TOOL_LIST_MAX_PAGES : Int = 1000

///|
pub const MCP_TOOL_LIST_MAX_TOOLS : Int = 100000

///|
pub struct McpToolListPage {
  tools : Array[McpToolInfo]
  next_cursor : String?
  ttl_ms : Int
  cache_scope : @protocol.McpCacheScope
} derive(Debug)

///|
pub fn list_params(cursor? : String? = None) -> Map[String, Json] {
  let params = Map([])
  match cursor {
    Some(value) => params["cursor"] = value.to_json()
    None => ()
  }
  params
}

///|
// The RPC envelope is decoded by the transport, before validating this result.
pub fn decode_list_result(
  result : Json,
  modern? : Bool = false,
) -> McpToolListPage raise @protocol.McpProtocolError {
  let obj = match result {
    Object(value) => value
    _ => raise InvalidResponse("tools/list result must be object")
  }
  @protocol.require_complete_result(
    result,
    required=modern,
    operation="tools/list",
  )
  let tools = match obj.get("tools") {
    Some(Array(value)) => value.map(decode_tool)
    _ => raise InvalidResponse("tools/list result missing tools")
  }
  let next_cursor = match obj.get("nextCursor") {
    Some(String(value)) => Some(value)
    Some(_) => raise InvalidResponse("tools/list nextCursor must be string")
    None => None
  }
  let ttl_ms = match obj.get("ttlMs") {
    Some(Number(value, ..)) if value.trunc() == value &&
      value >= 0.0 &&
      value <= 2147483647.0 => value.to_int()
    _ => 0
  }
  let cache_scope = match obj.get("cacheScope") {
    Some(String("public")) => @protocol.McpCacheScope::Public
    _ => Private
  }
  { tools, next_cursor, ttl_ms, cache_scope }
}

///|
// stdio lists do not impose the HTTP header-schema or cache-scope policy.
pub async fn list(
  fetch_page : async (String?) -> Json,
  max_pages? : Int = MCP_TOOL_LIST_MAX_PAGES,
  max_tools? : Int = MCP_TOOL_LIST_MAX_TOOLS,
) -> Array[McpToolInfo] {
  let pagination = tool_pagination(max_pages~, max_tools~)
  let tools = []
  for ;; {
    let cursor = pagination.begin_page()
    let page = decode_list_result(fetch_page(cursor), modern=true)
    let has_next = pagination.accept_page(page)
    tools.append(page.tools[:])
    if !has_next {
      break tools
    }
  }
}
