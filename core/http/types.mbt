///|
pub struct HttpRequest {
  http_method : String
  url : String
  headers : Map[String, String]
  body : String
}

///|
pub struct HttpResponse {
  status_code : Int
  content_type : String?
  headers : Map[String, String]
  body : String
}

///|
pub struct Endpoint {
  url : String
  headers : Map[String, String]
  mode : @config.McpConnectionMode
}

///|
pub struct McpToolListResult {
  tools : Array[@protocol.McpToolInfo]
  ttl_ms : Int
  cache_scope : @protocol.McpCacheScope
}

///|
pub fn mcp_tool_list_result(
  tools~ : Array[@protocol.McpToolInfo],
  ttl_ms? : Int = 0,
  cache_scope? : @protocol.McpCacheScope = @protocol.McpCacheScope::Private,
) -> McpToolListResult {
  { tools, ttl_ms, cache_scope }
}

///|
pub fn http_endpoint(
  url~ : String,
  headers? : Map[String, String] = Map([]),
  mode? : @config.McpConnectionMode = @config.McpConnectionMode::Auto,
) -> Endpoint {
  { url, headers, mode }
}

///|
pub fn http_response(
  status_code~ : Int,
  content_type? : String? = None,
  headers? : Map[String, String] = Map([]),
  body~ : String,
) -> HttpResponse {
  { status_code, content_type, headers, body }
}
