///|
priv struct ToolCacheEntry {
  tools : Array[@mcp_client.McpToolInfo]
  expires_at_ms : Int64
}

///|
let tool_cache : Map[String, ToolCacheEntry] = Map([])

///|
let tool_cache_order : Array[String] = []

///|
const MAX_TOOL_CACHE_ENTRIES : Int = 256

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
  mode? : @config.McpConnectionMode = @config.McpConnectionMode::Auto,
) -> Json raise McpHttpError {
  let tool_definition = cached_tool_definition(url, headers, mode, tool_name)
  @core_http.call_tool(
    native_fetch,
    @core_http.http_endpoint(url~, headers~, mode~),
    tool_name~,
    arguments~,
    tool_definition~,
    on_catalog_refresh=result => cache_tool_result(url, headers, mode, result),
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
  cache_tool_result(url, headers, mode, result)
  result.tools.copy()
}

///|
fn cache_tool_result(
  url : String,
  headers : Map[String, String],
  mode : @config.McpConnectionMode,
  result : @core_http.McpToolListResult,
) -> Unit {
  let public_key = tool_cache_key(url, mode, Map([]))
  let private_key = tool_cache_key(url, mode, headers)
  remove_cache_entry(public_key)
  remove_cache_entry(private_key)
  if result.ttl_ms > 0 {
    let key = if result.cache_scope == @mcp_client.McpCacheScope::Public {
      public_key
    } else {
      private_key
    }
    tool_cache[key] = {
      tools: clone_tool_list(result.tools),
      expires_at_ms: now_ms() + result.ttl_ms.to_int64(),
    }
    touch_cache_key(key)
    evict_tool_cache()
  }
}

///|
fn cached_tool_definition(
  url : String,
  headers : Map[String, String],
  mode : @config.McpConnectionMode,
  tool_name : String,
) -> @mcp_client.McpToolInfo? {
  let public_key = tool_cache_key(url, mode, Map([]))
  let private_key = tool_cache_key(url, mode, headers)
  let tools = match cached_tools(public_key) {
    Some(value) => Some(value)
    None => cached_tools(private_key)
  }
  match tools {
    Some(values) =>
      match values.search_by(tool => tool.name == tool_name) {
        Some(index) => Some(values[index])
        None => None
      }
    None => None
  }
}

///|
fn cached_tools(key : String) -> Array[@mcp_client.McpToolInfo]? {
  match tool_cache.get(key) {
    Some(entry) if entry.expires_at_ms > now_ms() => {
      touch_cache_key(key)
      Some(clone_tool_list(entry.tools))
    }
    Some(_) => {
      remove_cache_entry(key)
      None
    }
    None => None
  }
}

///|
fn clone_tool_list(
  tools : Array[@mcp_client.McpToolInfo],
) -> Array[@mcp_client.McpToolInfo] {
  tools.map(tool => {
    @mcp_client.mcp_tool_info(
      name=tool.name,
      description=tool.description,
      input_schema=clone_json(tool.input_schema),
      output_schema=tool.output_schema.map(clone_json),
    )
  })
}

///|
fn clone_json(value : Json) -> Json {
  match value {
    Object(obj) => {
      let clone : Map[String, Json] = Map([])
      for key, child in obj {
        clone[key] = clone_json(child)
      }
      Json::object(clone)
    }
    Array(items) => Json::array(items.map(clone_json))
    _ => value
  }
}

///|
pub fn tool_cache_key(
  url : String,
  mode : @config.McpConnectionMode,
  headers : Map[String, String],
) -> String {
  let pairs = []
  for key, value in headers {
    pairs.push(length_prefixed(key.to_lower()) + length_prefixed(value))
  }
  pairs.sort()
  let material = length_prefixed(url) +
    length_prefixed(connection_mode_key(mode)) +
    pairs.join("")
  let bytes = @encoding.encode(@encoding.Encoding::UTF8, material)
  @crypto.sha256(bytes).iter().map(byte => byte.to_hex()).join("")
}

///|
fn length_prefixed(value : String) -> String {
  value.length().to_string() + ":" + value
}

///|
fn remove_cache_entry(key : String) -> Unit {
  tool_cache.remove(key)
  for i, value in tool_cache_order {
    if value == key {
      ignore(tool_cache_order.remove(i))
      break
    }
  }
}

///|
fn touch_cache_key(key : String) -> Unit {
  for i, value in tool_cache_order {
    if value == key {
      ignore(tool_cache_order.remove(i))
      break
    }
  }
  tool_cache_order.push(key)
}

///|
fn evict_tool_cache() -> Unit {
  while tool_cache_order.length() > MAX_TOOL_CACHE_ENTRIES {
    if tool_cache_order.is_empty() {
      break
    }
    let key = tool_cache_order[0]
    ignore(tool_cache_order.remove(0))
    tool_cache.remove(key)
  }
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
  )
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
      McpHttpError::Network(message)
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
  for name, value in headers {
    if name.equal_ignore_ascii_case(key) {
      return Some(value)
    }
  }
  None
}
