///|
suberror McpHttpError {
  HttpStatus(Int)
  Network(String)
  Protocol(String)
  Negotiation(String)
} derive(Debug)

///|
pub fn mcp_http_status_code(error : McpHttpError) -> Int? {
  match error {
    HttpStatus(code) => Some(code)
    _ => None
  }
}

///|
pub fn mcp_http_is_network_error(error : McpHttpError) -> Bool {
  match error {
    Network(_) => true
    _ => false
  }
}

///|
pub fn mcp_http_is_protocol_error(error : McpHttpError) -> Bool {
  match error {
    Protocol(_) | Negotiation(_) => true
    _ => false
  }
}

///|
pub fn mcp_http_negotiation_message(error : McpHttpError) -> String? {
  match error {
    Negotiation(message) => Some(message)
    _ => None
  }
}

///|
pub async fn http_mcp_call_tool(
  url~ : String,
  headers~ : Map[String, String],
  tool_name~ : String,
  arguments~ : Json,
  mode? : @config.McpConnectionMode = Auto,
) -> Json raise McpHttpError {
  let tool_definition = default_tool_catalog_cache.find_tool(
    url, headers, mode, tool_name,
  )
  @core_http.call_tool(
    native_fetch,
    @core_http.http_endpoint(url~, headers~, mode~),
    tool_name~,
    arguments~,
    tool_definition~,
    on_catalog_refresh=result => {
      default_tool_catalog_cache.put(url, headers, mode, result)
    },
  ) catch {
    error => raise core_error_to_native(error)
  }
}

///|
pub async fn http_mcp_list_tools(
  url~ : String,
  headers~ : Map[String, String],
  mode? : @config.McpConnectionMode = Auto,
) -> Array[@mcp_client.McpToolInfo] raise McpHttpError {
  match default_tool_catalog_cache.get(url, headers, mode) {
    Some(value) => return value
    None => ()
  }
  let result = @core_http.list_tools_with_cache_hint(
    native_fetch,
    @core_http.http_endpoint(url~, headers~, mode~),
  ) catch {
    error => raise core_error_to_native(error)
  }
  default_tool_catalog_cache.put(url, headers, mode, result)
  result.tools.copy()
}

///|
fn core_error_to_native(error : @core_http.McpHttpClientError) -> McpHttpError {
  match error {
    HttpStatus(code) => HttpStatus(code)
    Protocol(message) => Protocol(message)
    Network(message) => Network(message)
    HeaderMismatch(message) => Negotiation("header mismatch: " + message)
    MissingRequiredClientCapability(message) =>
      Negotiation("missing required client capability: " + message)
    UnsupportedProtocolVersion(supported) =>
      Negotiation(
        "unsupported MCP protocol version; supported: " + supported.join(", "),
      )
    ModeProtocolIncompatible(mode, protocol) =>
      Negotiation(
        "protocol mode " + mode + " is incompatible with MCP " + protocol,
      )
    RemoteError(code, message) =>
      Protocol("json-rpc error " + code.to_string() + ": " + message)
  }
}
