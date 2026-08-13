///|
priv struct ToolCacheEntry {
  tools : Array[@mcp_client.McpToolInfo]
  expires_at_ms : Int64
}

///|
let tool_cache : Map[String, ToolCacheEntry] = Map([])

///|
suberror McpHttpError {
  HttpStatus(Int)
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
  mode? : @config.McpConnectionMode = @config.McpConnectionMode::Auto,
) -> Json raise McpHttpError {
  @core_http.call_tool(
    native_fetch,
    @core_http.http_endpoint(url~, headers~, mode~),
    tool_name~,
    arguments~,
  ) catch {
    error => raise core_error_to_native(error)
  }
}

///|
pub async fn http_mcp_list_tools(
  url~ : String,
  headers~ : Map[String, String],
  mode? : @config.McpConnectionMode = @config.McpConnectionMode::Auto,
) -> Array[@mcp_client.McpToolInfo] raise McpHttpError {
  let public_key = tool_cache_key(url, mode, Map([]))
  let private_key = tool_cache_key(url, mode, headers)
  match cached_tools(public_key) {
    Some(value) => return value
    None =>
      match cached_tools(private_key) {
        Some(value) => return value
        None => ()
      }
  }
  let result = @core_http.list_tools_with_cache_hint(
    native_fetch,
    @core_http.http_endpoint(url~, headers~, mode~),
  ) catch {
    error => raise core_error_to_native(error)
  }
  if result.ttl_ms > 0 {
    let key = if result.cache_scope == "public" {
      public_key
    } else {
      private_key
    }
    tool_cache[key] = {
      tools: result.tools,
      expires_at_ms: now_ms() + result.ttl_ms.to_int64(),
    }
  }
  result.tools
}

///|
fn cached_tools(key : String) -> Array[@mcp_client.McpToolInfo]? {
  match tool_cache.get(key) {
    Some(entry) if entry.expires_at_ms > now_ms() => Some(entry.tools)
    Some(_) => {
      tool_cache.remove(key)
      None
    }
    None => None
  }
}

///|
fn tool_cache_key(
  url : String,
  mode : @config.McpConnectionMode,
  headers : Map[String, String],
) -> String {
  let pairs = []
  for key, value in headers {
    pairs.push(key.to_lower() + "=" + value)
  }
  pairs.sort()
  url + "\n" + connection_mode_key(mode) + "\n" + pairs.join("\n")
}

///|
fn connection_mode_key(mode : @config.McpConnectionMode) -> String {
  match mode {
    Auto => "auto"
    Stateful => "stateful"
    Stateless => "stateless"
  }
}

///|
fn now_ms() -> Int64 {
  @env.now().reinterpret_as_int64()
}

///|
async fn native_fetch(
  request : @core_http.HttpRequest,
) -> @core_http.HttpResponse {
  let (response, data) = @async_http.post(
    request.url,
    request.body,
    headers=request.headers,
  ) catch {
    error =>
      return @core_http.http_response(
        status_code=599,
        content_type=Some("text/plain"),
        body=error.to_string(),
      )
  }
  let content_type = header(response.headers, "content-type")
  let body = if response.code == 202 {
    ""
  } else {
    data.text() catch {
      _ => ""
    }
  }
  @core_http.http_response(
    status_code=response.code,
    content_type~,
    headers=response.headers,
    body~,
  )
}

///|
fn core_error_to_native(error : @core_http.McpHttpClientError) -> McpHttpError {
  match error {
    @core_http.McpHttpClientError::HttpStatus(code) =>
      McpHttpError::HttpStatus(code)
    @core_http.McpHttpClientError::Protocol(message) =>
      McpHttpError::Protocol(message)
    @core_http.McpHttpClientError::Network(message) =>
      McpHttpError::Protocol(message)
    @core_http.McpHttpClientError::HeaderMismatch(message) =>
      McpHttpError::Negotiation("header mismatch: " + message)
    @core_http.McpHttpClientError::MissingRequiredClientCapability(message) =>
      McpHttpError::Negotiation(
        "missing required client capability: " + message,
      )
    @core_http.McpHttpClientError::UnsupportedProtocolVersion(supported) =>
      McpHttpError::Negotiation(
        "unsupported MCP protocol version; supported: " + supported.join(", "),
      )
    @core_http.McpHttpClientError::ModeProtocolIncompatible(mode, protocol) =>
      McpHttpError::Negotiation(
        "protocol mode " + mode + " is incompatible with MCP " + protocol,
      )
    @core_http.McpHttpClientError::RemoteError(code, message) =>
      McpHttpError::Protocol(
        "json-rpc error " + code.to_string() + ": " + message,
      )
  }
}

///|
fn header(headers : Map[String, String], key : String) -> String? {
  match headers.get(key) {
    Some(value) => Some(value)
    None => headers.get(key.to_lower())
  }
}
