///|
priv struct ToolCacheEntry {
  catalog_id : String
  tools : Array[@mcp_client.McpToolInfo]
  expires_at_ms : Int64
}

///|
priv struct ToolCatalogCache {
  entries : Map[String, ToolCacheEntry]
  order : Array[String]
  max_entries : Int
  clock : () -> Int64
}

///|
const MAX_TOOL_CACHE_ENTRIES : Int = 256

///|
let default_tool_catalog_cache : ToolCatalogCache = tool_catalog_cache(
  max_entries=MAX_TOOL_CACHE_ENTRIES,
  clock=now_ms,
)

///|
fn tool_catalog_cache(
  max_entries~ : Int,
  clock~ : () -> Int64,
) -> ToolCatalogCache {
  { entries: Map([]), order: [], max_entries, clock }
}

///|
fn ToolCatalogCache::get(
  self : ToolCatalogCache,
  url : String,
  headers : Map[String, String],
  mode : @config.McpConnectionMode,
) -> Array[@mcp_client.McpToolInfo]? {
  let public_key = tool_cache_key(url, mode, Map([]))
  let private_key = tool_cache_key(url, mode, headers)
  match self.get_by_key(public_key) {
    Some(value) => Some(value)
    None => self.get_by_key(private_key)
  }
}

///|
fn ToolCatalogCache::put(
  self : ToolCatalogCache,
  url : String,
  headers : Map[String, String],
  mode : @config.McpConnectionMode,
  result : @core_http.McpToolListResult,
) -> Unit {
  let public_key = tool_cache_key(url, mode, Map([]))
  let private_key = tool_cache_key(url, mode, headers)
  let catalog_id = tool_catalog_id(url, mode)
  if result.cache_scope == Public {
    self.remove_catalog(catalog_id)
  } else {
    self.remove(public_key)
    self.remove(private_key)
  }
  if result.ttl_ms > 0 {
    let key = if result.cache_scope == Public {
      public_key
    } else {
      private_key
    }
    self.entries[key] = {
      catalog_id,
      tools: clone_tool_list(result.tools),
      expires_at_ms: (self.clock)() + result.ttl_ms.to_int64(),
    }
    self.touch(key)
    self.evict()
  }
}

///|
fn ToolCatalogCache::get_by_key(
  self : ToolCatalogCache,
  key : String,
) -> Array[@mcp_client.McpToolInfo]? {
  match self.entries.get(key) {
    Some(entry) if entry.expires_at_ms > (self.clock)() => {
      self.touch(key)
      Some(clone_tool_list(entry.tools))
    }
    Some(_) => {
      self.remove(key)
      None
    }
    None => None
  }
}

///|
fn ToolCatalogCache::remove(self : ToolCatalogCache, key : String) -> Unit {
  self.entries.remove(key)
  for i, value in self.order {
    if value == key {
      ignore(self.order.remove(i))
      break
    }
  }
}

///|
fn ToolCatalogCache::remove_catalog(
  self : ToolCatalogCache,
  catalog_id : String,
) -> Unit {
  let removals = []
  for key, entry in self.entries {
    if entry.catalog_id == catalog_id {
      removals.push(key)
    }
  }
  for key in removals {
    self.remove(key)
  }
}

///|
fn ToolCatalogCache::touch(self : ToolCatalogCache, key : String) -> Unit {
  for i, value in self.order {
    if value == key {
      ignore(self.order.remove(i))
      break
    }
  }
  self.order.push(key)
}

///|
fn ToolCatalogCache::evict(self : ToolCatalogCache) -> Unit {
  while self.order.length() > self.max_entries {
    let key = self.order[0]
    ignore(self.order.remove(0))
    self.entries.remove(key)
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
fn tool_catalog_id(url : String, mode : @config.McpConnectionMode) -> String {
  hash_tool_cache_material(
    length_prefixed(url) + length_prefixed(connection_mode_key(mode)),
  )
}

///|
fn tool_cache_key(
  url : String,
  mode : @config.McpConnectionMode,
  headers : Map[String, String],
) -> String {
  let pairs = []
  for key, value in headers {
    pairs.push(length_prefixed(key.to_lower()) + length_prefixed(value))
  }
  pairs.sort()
  hash_tool_cache_material(
    length_prefixed(url) +
    length_prefixed(connection_mode_key(mode)) +
    pairs.join(""),
  )
}

///|
fn hash_tool_cache_material(material : String) -> String {
  let bytes = @encoding.encode(UTF8, material)
  @crypto.sha256(bytes).iter().map(byte => byte.to_hex()).join("")
}

///|
fn length_prefixed(value : String) -> String {
  value.length().to_string() + ":" + value
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
fn ToolCatalogCache::find_tool(
  self : ToolCatalogCache,
  url : String,
  headers : Map[String, String],
  mode : @config.McpConnectionMode,
  tool_name : String,
) -> @mcp_client.McpToolInfo? {
  match self.get(url, headers, mode) {
    Some(tools) =>
      match tools.search_by(tool => tool.name == tool_name) {
        Some(index) => Some(tools[index])
        None => None
      }
    None => None
  }
}

///|
fn now_ms() -> Int64 {
  @env.now().reinterpret_as_int64()
}
