///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp stdio: initialize then call tool" {
  let script =
    #|i=0
    #|while IFS= read -r line; do
    #|  i=$((i + 1))
    #|  if [ "$i" = "1" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-03-26","capabilities":{},"serverInfo":{"name":"srv"}}}'
    #|  elif [ "$i" = "3" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"ok":true,"transport":"stdio"}}'
    #|  fi
    #|done
  let result = stdio_mcp_call_tool(
    command="/bin/sh",
    args=["-c", script],
    env=Map([]),
    cwd=None,
    tool_name="search",
    arguments=Json::object({ "q": Json::string("moonbit") }),
  )
  inspect(result.stringify(), content="{\"ok\":true,\"transport\":\"stdio\"}")
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp stdio: lists tools after initialize" {
  let script =
    #|i=0
    #|while IFS= read -r line; do
    #|  i=$((i + 1))
    #|  if [ "$i" = "1" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-03-26","capabilities":{},"serverInfo":{"name":"srv"}}}'
    #|  elif [ "$i" = "3" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"search","description":"Search things","inputSchema":{"type":"object"}}]}}'
    #|  fi
    #|done
  let tools = stdio_mcp_list_tools(
    command="/bin/sh",
    args=["-c", script],
    env=Map([]),
    cwd=None,
  )
  @debug.debug_inspect(
    tools,
    content=(
      #|[
      #|  {
      #|    name: "search",
      #|    description: Some("Search things"),
      #|    input_schema: Object({ "type": String("object") }),
      #|    output_schema: None,
      #|  },
      #|]
    ),
  )
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp stdio: auto discovers stateless MCP 2026" {
  let script =
    #|while IFS= read -r line; do
    #|  case "$line" in
    #|    *'"method":"server/discover"'*)
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"],"capabilities":{}}}'
    #|      ;;
    #|    *'"method":"tools/list"'*)
    #|      if printf '%s' "$line" | grep -q 'io.modelcontextprotocol/clientInfo'; then
    #|        printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"modern","inputSchema":{}}]}}'
    #|      fi
    #|      ;;
    #|  esac
    #|done
  let tools = stdio_mcp_list_tools(
    command="/bin/sh",
    args=["-c", script],
    env=Map([]),
    cwd=None,
    mode=@config.McpConnectionMode::Auto,
  )
  inspect(tools[0].name, content="modern")
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp stdio: auto falls back after method not found" {
  let script =
    #|i=0
    #|while IFS= read -r line; do
    #|  i=$((i + 1))
    #|  if [ "$i" = "1" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"not found"}}'
    #|  elif [ "$i" = "2" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","capabilities":{}}}'
    #|  elif [ "$i" = "4" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"legacy","inputSchema":{}}]}}'
    #|  fi
    #|done
  let tools = stdio_mcp_list_tools(
    command="/bin/sh",
    args=["-c", script],
    env=Map([]),
    cwd=None,
    mode=@config.McpConnectionMode::Auto,
  )
  inspect(tools[0].name, content="legacy")
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp stdio: stateless rejects method not found" {
  let script =
    #|while IFS= read -r line; do
    #|  printf '%s\n' '{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"not found"}}'
    #|done
  try
    stdio_mcp_list_tools(
      command="/bin/sh",
      args=["-c", script],
      env=Map([]),
      cwd=None,
      mode=@config.McpConnectionMode::Stateless,
    )
  catch {
    McpStdioError::Protocol(_) => ()
    _ => fail("expected protocol error")
  } noraise {
    _ => fail("expected stateless negotiation to fail")
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp stdio: persistent client reuses initialized process" {
  let script =
    #|i=0
    #|while IFS= read -r line; do
    #|  i=$((i + 1))
    #|  if [ "$i" = "1" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-03-26","capabilities":{},"serverInfo":{"name":"srv"}}}'
    #|  elif [ "$i" = "3" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"call":1}}'
    #|  elif [ "$i" = "4" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":3,"result":{"call":2}}'
    #|  fi
    #|done
  @async.with_task_group(group => {
    let client = stdio_mcp_connect(
      group,
      command="/bin/sh",
      args=["-c", script],
      env=Map([]),
      cwd=None,
    )
    let first = client.call_tool(
      tool_name="search",
      arguments=Json::empty_object(),
    )
    let second = client.call_tool(
      tool_name="search",
      arguments=Json::empty_object(),
    )
    client.close()
    inspect(
      first.stringify() + "|" + second.stringify(),
      content="{\"call\":1}|{\"call\":2}",
    )
  })
}
