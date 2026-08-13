///|
test "native tool cache: expires entries using injected clock" {
  let now = Ref(1000L)
  let cache = tool_catalog_cache(max_entries=2, clock=() => now.val)
  cache.put(
    "https://example.test/mcp",
    Map([]),
    @config.McpConnectionMode::Auto,
    @core_http.mcp_tool_list_result(
      tools=[@mcp_client.mcp_tool_info(name="search", input_schema={})],
      ttl_ms=10,
    ),
  )
  inspect(
    cache.get(
      "https://example.test/mcp",
      Map([]),
      @config.McpConnectionMode::Auto,
    )
    is Some(_),
    content="true",
  )
  now.val = 1010L
  inspect(
    cache.get(
      "https://example.test/mcp",
      Map([]),
      @config.McpConnectionMode::Auto,
    )
    is None,
    content="true",
  )
}

///|
test "native tool cache: public refresh supersedes private variants" {
  let now = Ref(1000L)
  let cache = tool_catalog_cache(max_entries=4, clock=() => now.val)
  let url = "https://example.test/mcp"
  cache.put(
    url,
    { "Authorization": "Bearer old" },
    @config.McpConnectionMode::Auto,
    @core_http.mcp_tool_list_result(
      tools=[@mcp_client.mcp_tool_info(name="private", input_schema={})],
      ttl_ms=100,
      cache_scope=@mcp_client.McpCacheScope::Private,
    ),
  )
  cache.put(
    url,
    { "Authorization": "Bearer new" },
    @config.McpConnectionMode::Auto,
    @core_http.mcp_tool_list_result(
      tools=[@mcp_client.mcp_tool_info(name="public", input_schema={})],
      ttl_ms=10,
      cache_scope=@mcp_client.McpCacheScope::Public,
    ),
  )
  now.val = 1010L
  inspect(
    cache.get(
      url,
      { "Authorization": "Bearer old" },
      @config.McpConnectionMode::Auto,
    )
    is None,
    content="true",
  )
}

///|
test "native tool cache: evicts least recently used entries" {
  let cache = tool_catalog_cache(max_entries=2, clock=() => 1000L)
  for url in ["https://one", "https://two"] {
    cache.put(
      url,
      Map([]),
      @config.McpConnectionMode::Auto,
      @core_http.mcp_tool_list_result(
        tools=[@mcp_client.mcp_tool_info(name=url, input_schema={})],
        ttl_ms=10,
      ),
    )
  }
  ignore(cache.get("https://one", Map([]), @config.McpConnectionMode::Auto))
  cache.put(
    "https://three",
    Map([]),
    @config.McpConnectionMode::Auto,
    @core_http.mcp_tool_list_result(
      tools=[@mcp_client.mcp_tool_info(name="three", input_schema={})],
      ttl_ms=10,
    ),
  )
  inspect(
    cache.get("https://one", Map([]), @config.McpConnectionMode::Auto)
    is Some(_),
    content="true",
  )
  inspect(
    cache.get("https://two", Map([]), @config.McpConnectionMode::Auto) is None,
    content="true",
  )
}
