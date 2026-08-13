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
    #|        printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","tools":[{"name":"modern","inputSchema":{}}]}}'
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
async test "mcp stdio: paginates stateless tool lists" {
  let script =
    #|while IFS= read -r line; do
    #|  case "$line" in
    #|    *'"method":"server/discover"'*)
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"]}}'
    #|      ;;
    #|    *'"cursor":"next"'*)
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":3,"result":{"resultType":"complete","tools":[{"name":"second","inputSchema":{}}]}}'
    #|      ;;
    #|    *'"method":"tools/list"'*)
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","tools":[{"name":"first","inputSchema":{}}],"nextCursor":"next"}}'
    #|      ;;
    #|  esac
    #|done
  let tools = stdio_mcp_list_tools(
    command="/bin/sh",
    args=["-c", script],
    env=Map([]),
    cwd=None,
    mode=@config.McpConnectionMode::Stateless,
  )
  inspect(tools.map(tool => tool.name).join(","), content="first,second")
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp stdio: bounds skipped messages while awaiting responses" {
  let script =
    #|while IFS= read -r line; do
    #|  case "$line" in
    #|    *'"method":"server/discover"'*)
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"]}}'
    #|      ;;
    #|    *'"method":"tools/list"'*)
    #|      i=0
    #|      while [ "$i" -lt 1001 ]; do
    #|        printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/progress","params":{}}'
    #|        i=$((i + 1))
    #|      done
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","tools":[]}}'
    #|      ;;
    #|  esac
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
    McpStdioError::Protocol(message) =>
      inspect(message, content="too many messages while awaiting MCP response")
    _ => fail("expected protocol error")
  } noraise {
    _ => fail("expected skipped message limit")
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp stdio: poisons connection after wrong response id" {
  let script =
    #|while IFS= read -r line; do
    #|  case "$line" in
    #|    *'"method":"server/discover"'*)
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"]}}'
    #|      ;;
    #|    *'"method":"tools/list"'*)
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":999,"result":{"resultType":"complete","tools":[]}}'
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","tools":[]}}'
    #|      ;;
    #|  esac
    #|done
  @async.with_task_group(group => {
    let client = stdio_mcp_connect(
      group,
      command="/bin/sh",
      args=["-c", script],
      env=Map([]),
      cwd=None,
      mode=@config.McpConnectionMode::Stateless,
    )
    defer client.close()
    try client.list_tools() catch {
      McpStdioError::Protocol(message) =>
        inspect(message, content="unexpected MCP response id")
      _ => fail("expected protocol error")
    } noraise {
      _ => fail("expected wrong response id to fail")
    }
    try client.list_tools() catch {
      McpStdioError::Protocol(message) =>
        inspect(
          message,
          content="stdio connection is unusable after protocol desynchronization",
        )
      _ => fail("expected poisoned connection error")
    } noraise {
      _ => fail("expected poisoned connection to reject operation")
    }
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp stdio: times out silent tool operations" {
  let script =
    #|while IFS= read -r line; do
    #|  case "$line" in
    #|    *'"method":"server/discover"'*)
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"]}}'
    #|      ;;
    #|    *) sleep 10 ;;
    #|  esac
    #|done
  try
    stdio_mcp_list_tools(
      command="/bin/sh",
      args=["-c", script],
      env=Map([]),
      cwd=None,
      mode=@config.McpConnectionMode::Stateless,
      response_timeout_ms=50,
    )
  catch {
    McpStdioError::Timeout => ()
    _ => fail("expected timeout error")
  } noraise {
    _ => fail("expected operation timeout")
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp stdio: rejects operations after a response timeout" {
  let script =
    #|while IFS= read -r line; do
    #|  case "$line" in
    #|    *'"method":"server/discover"'*)
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"]}}'
    #|      ;;
    #|    *'"method":"tools/list"'*)
    #|      sleep 1
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","tools":[]}}'
    #|      ;;
    #|    *'"method":"tools/call"'*)
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":3,"result":{"resultType":"complete","content":[]}}'
    #|      ;;
    #|  esac
    #|done
  @async.with_task_group(group => {
    let client = stdio_mcp_connect(
      group,
      command="/bin/sh",
      args=["-c", script],
      env=Map([]),
      cwd=None,
      mode=@config.McpConnectionMode::Stateless,
      response_timeout_ms=50,
    )
    try client.list_tools() catch {
      McpStdioError::Timeout => ()
      _ => fail("expected timeout")
    } noraise {
      _ => fail("expected timeout")
    }
    try
      client.call_tool(tool_name="search", arguments=Json::empty_object())
    catch {
      McpStdioError::Protocol(message) =>
        inspect(message, content="stdio connection is unusable after timeout")
      _ => fail("expected poisoned connection error")
    } noraise {
      _ => fail("expected poisoned connection to reject operation")
    }
    client.close()
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp stdio: applies one timeout to complete pagination" {
  let script =
    #|while IFS= read -r line; do
    #|  case "$line" in
    #|    *'"method":"server/discover"'*)
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"]}}'
    #|      ;;
    #|    *'"cursor":"next"'*)
    #|      sleep 0.08
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":3,"result":{"resultType":"complete","tools":[]}}'
    #|      ;;
    #|    *'"method":"tools/list"'*)
    #|      sleep 0.08
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","tools":[],"nextCursor":"next"}}'
    #|      ;;
    #|  esac
    #|done
  try
    stdio_mcp_list_tools(
      command="/bin/sh",
      args=["-c", script],
      env=Map([]),
      cwd=None,
      mode=@config.McpConnectionMode::Stateless,
      response_timeout_ms=120,
    )
  catch {
    McpStdioError::Timeout => ()
    _ => fail("expected pagination timeout")
  } noraise {
    _ => fail("expected complete pagination to time out")
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp stdio: bounds stateless tool pagination" {
  let script =
    #|while IFS= read -r line; do
    #|  case "$line" in
    #|    *'"method":"server/discover"'*)
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"]}}'
    #|      ;;
    #|    *'"id":2'*)
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","tools":[],"nextCursor":"two"}}'
    #|      ;;
    #|    *'"id":3'*)
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":3,"result":{"resultType":"complete","tools":[],"nextCursor":"three"}}'
    #|      ;;
    #|  esac
    #|done
  try
    stdio_mcp_list_tools(
      command="/bin/sh",
      args=["-c", script],
      env=Map([]),
      cwd=None,
      mode=@config.McpConnectionMode::Stateless,
      max_pages=2,
    )
  catch {
    McpStdioError::Protocol(_) => ()
    _ => fail("expected pagination limit")
  } noraise {
    _ => fail("expected pagination limit")
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp stdio: preserves modern protocol diagnostics" {
  let script =
    #|while IFS= read -r line; do
    #|  case "$line" in
    #|    *'"method":"server/discover"'*)
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"]}}'
    #|      ;;
    #|    *'"method":"tools/list"'*)
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"tools":[]}}'
    #|      ;;
    #|  esac
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
    McpStdioError::Protocol(message) =>
      inspect(message, content="tools/list result missing resultType")
    _ => fail("expected protocol error")
  } noraise {
    _ => fail("expected invalid modern response")
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp stdio: modern tool results require resultType" {
  for rpc_name in ["tools/list", "tools/call"] {
    let script =
      #|while IFS= read -r line; do
      #|  case "$line" in
      #|    *'"method":"server/discover"'*)
      #|      printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"]}}'
      #|      ;;
      #|    *'"method":"'"$RPC_NAME"'"'*)
      #|      if [ "$RPC_NAME" = "tools/list" ]; then
      #|        printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"tools":[]}}'
      #|      else
      #|        printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"content":[]}}'
      #|      fi
      #|      ;;
      #|  esac
      #|done
    try {
      if rpc_name == "tools/list" {
        ignore(
          stdio_mcp_list_tools(
            command="/bin/sh",
            args=["-c", script],
            env={ "RPC_NAME": rpc_name },
            cwd=None,
            mode=@config.McpConnectionMode::Stateless,
          ),
        )
      } else {
        ignore(
          stdio_mcp_call_tool(
            command="/bin/sh",
            args=["-c", script],
            env={ "RPC_NAME": rpc_name },
            cwd=None,
            tool_name="run",
            arguments=Json::empty_object(),
            mode=@config.McpConnectionMode::Stateless,
          ),
        )
      }
    } catch {
      McpStdioError::Protocol(_) => ()
      _ => fail("expected protocol error")
    } noraise {
      _ => fail("expected missing resultType to fail")
    }
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp stdio: auto falls back after method not found" {
  let marker = "/tmp/mcpx-stdio-method-not-found.marker"
  @fs.remove_file(marker) catch {
    _ => ()
  }
  let script =
    #|if [ ! -f "$MARKER" ]; then
    #|  touch "$MARKER"
    #|  read -r line
    #|  printf '%s\n' '{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"not found"}}'
    #|else
    #|  i=0
    #|  while IFS= read -r line; do
    #|    i=$((i + 1))
    #|    if [ "$i" = "1" ]; then
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","capabilities":{}}}'
    #|    elif [ "$i" = "3" ]; then
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"legacy","inputSchema":{}}]}}'
    #|    fi
    #|  done
    #|fi
  let tools = stdio_mcp_list_tools(
    command="/bin/sh",
    args=["-c", script],
    env={ "MARKER": marker },
    cwd=None,
    mode=@config.McpConnectionMode::Auto,
  )
  inspect(tools[0].name, content="legacy")
  @fs.remove_file(marker) catch {
    _ => ()
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp stdio: auto restarts process after legacy probe" {
  let marker = "/tmp/mcpx-stdio-probe-restart.marker"
  @fs.remove_file(marker) catch {
    _ => ()
  }
  let script =
    #|if [ ! -f "$MARKER" ]; then
    #|  touch "$MARKER"
    #|  while IFS= read -r line; do
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"not found"}}'
    #|  done
    #|else
    #|  i=0
    #|  while IFS= read -r line; do
    #|    i=$((i + 1))
    #|    if [ "$i" = "1" ]; then
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","capabilities":{}}}'
    #|    elif [ "$i" = "3" ]; then
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"restarted","inputSchema":{}}]}}'
    #|    fi
    #|  done
    #|fi
  let tools = stdio_mcp_list_tools(
    command="/bin/sh",
    args=["-c", script],
    env={ "MARKER": marker },
    cwd=None,
    mode=@config.McpConnectionMode::Auto,
  )
  inspect(tools[0].name, content="restarted")
  @fs.remove_file(marker) catch {
    _ => ()
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp stdio: auto times out silent probe and restarts" {
  let marker = "/tmp/mcpx-stdio-probe-timeout.marker"
  @fs.remove_file(marker) catch {
    _ => ()
  }
  let script =
    #|if [ ! -f "$MARKER" ]; then
    #|  touch "$MARKER"
    #|  while IFS= read -r line; do sleep 10; done
    #|else
    #|  i=0
    #|  while IFS= read -r line; do
    #|    i=$((i + 1))
    #|    if [ "$i" = "1" ]; then
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","capabilities":{}}}'
    #|    elif [ "$i" = "3" ]; then
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"timeout-restarted","inputSchema":{}}]}}'
    #|    fi
    #|  done
    #|fi
  let tools = stdio_mcp_list_tools(
    command="/bin/sh",
    args=["-c", script],
    env={ "MARKER": marker },
    cwd=None,
    mode=@config.McpConnectionMode::Auto,
    probe_timeout_ms=50,
  )
  inspect(tools[0].name, content="timeout-restarted")
  @fs.remove_file(marker) catch {
    _ => ()
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp stdio: auto does not fallback on recognized modern errors" {
  for code in [-32020, -32021, -32022] {
    let marker = "/tmp/mcpx-stdio-modern-error-" + code.to_string() + ".marker"
    @fs.remove_file(marker) catch {
      _ => ()
    }
    @fs.remove_file(marker + ".fallback") catch {
      _ => ()
    }
    let script =
      #|if [ ! -f "$MARKER" ]; then
      #|  touch "$MARKER"
      #|  read -r line
      #|  printf '%s\n' '{"jsonrpc":"2.0","id":1,"error":{"code":'"$CODE"',"message":"modern error","data":{"supported":["2099-01-01"]}}}'
      #|else
      #|  touch "$MARKER.fallback"
      #|  i=0
      #|  while IFS= read -r line; do
      #|    i=$((i + 1))
      #|    if [ "$i" = "1" ]; then
      #|      printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","capabilities":{}}}'
      #|    elif [ "$i" = "3" ]; then
      #|      printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"tools":[]}}'
      #|    fi
      #|  done
      #|fi
    try
      stdio_mcp_list_tools(
        command="/bin/sh",
        args=["-c", script],
        env={ "MARKER": marker, "CODE": code.to_string() },
        cwd=None,
        mode=@config.McpConnectionMode::Auto,
      )
    catch {
      McpStdioError::Protocol(_) => ()
      _ => fail("expected protocol error")
    } noraise {
      _ => fail("expected recognized modern error")
    }
    inspect(@fs.path_exists(marker + ".fallback"), content="false")
    @fs.remove_file(marker) catch {
      _ => ()
    }
    @fs.remove_file(marker + ".fallback") catch {
      _ => ()
    }
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp stdio: auto does not fallback on arbitrary remote errors" {
  for code in [-32602, -32603, -32099] {
    let marker = "/tmp/mcpx-stdio-remote-error-" + code.to_string() + ".marker"
    @fs.remove_file(marker) catch {
      _ => ()
    }
    @fs.remove_file(marker + ".fallback") catch {
      _ => ()
    }
    let script =
      #|if [ ! -f "$MARKER" ]; then
      #|  touch "$MARKER"
      #|  read -r line
      #|  printf '%s\n' '{"jsonrpc":"2.0","id":1,"error":{"code":'"$CODE"',"message":"remote error"}}'
      #|else
      #|  touch "$MARKER.fallback"
      #|fi
    try
      stdio_mcp_list_tools(
        command="/bin/sh",
        args=["-c", script],
        env={ "MARKER": marker, "CODE": code.to_string() },
        cwd=None,
        mode=@config.McpConnectionMode::Auto,
      )
    catch {
      McpStdioError::Protocol(_) => ()
      _ => fail("expected protocol error")
    } noraise {
      _ => fail("expected remote error")
    }
    inspect(@fs.path_exists(marker + ".fallback"), content="false")
    @fs.remove_file(marker) catch {
      _ => ()
    }
    @fs.remove_file(marker + ".fallback") catch {
      _ => ()
    }
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp stdio: auto does not fallback on malformed modern responses" {
  let marker = "/tmp/mcpx-stdio-malformed-modern.marker"
  @fs.remove_file(marker) catch {
    _ => ()
  }
  @fs.remove_file(marker + ".fallback") catch {
    _ => ()
  }
  let script =
    #|if [ ! -f "$MARKER" ]; then
    #|  touch "$MARKER"
    #|  read -r line
    #|  printf '%s\n' '{"jsonrpc":"1.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"]}}'
    #|else
    #|  touch "$MARKER.fallback"
    #|fi
  try
    stdio_mcp_list_tools(
      command="/bin/sh",
      args=["-c", script],
      env={ "MARKER": marker },
      cwd=None,
      mode=@config.McpConnectionMode::Auto,
    )
  catch {
    McpStdioError::Protocol(_) => ()
    _ => fail("expected protocol error")
  } noraise {
    _ => fail("expected malformed response to fail")
  }
  inspect(@fs.path_exists(marker + ".fallback"), content="false")
  @fs.remove_file(marker) catch {
    _ => ()
  }
  @fs.remove_file(marker + ".fallback") catch {
    _ => ()
  }
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
async test "mcp stdio: serializes concurrent client operations" {
  let script =
    #|i=0
    #|while IFS= read -r line; do
    #|  i=$((i + 1))
    #|  if [ "$i" = "1" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-03-26","capabilities":{}}}'
    #|  elif [ "$i" = "3" ]; then
    #|    first="$line"
    #|    if IFS= read -r -t 1 second; then
    #|      printf '%s\n' '{"jsonrpc":"2.0","id":999,"error":{"code":-32603,"message":"concurrent request"}}'
    #|      exit 0
    #|    fi
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"call":1}}'
    #|  elif [ "$i" = "4" ]; then
    #|    printf '%s\n' '{"jsonrpc":"2.0","id":3,"result":{"call":2}}'
    #|  fi
    #|done
  @async.with_task_group(group => {
    let client = stdio_mcp_connect(
      group,
      command="/bin/bash",
      args=["-c", script],
      env=Map([]),
      cwd=None,
    )
    let results : Array[Json] = []
    for _ in 0..<2 {
      group.spawn_bg(no_wait=true, () => {
        let result = client.call_tool(
          tool_name="search",
          arguments=Json::empty_object(),
        )
        results.push(result)
      })
    }
    while results.length() < 2 {
      @async.sleep(10)
    }
    client.close()
    results.sort_by((left, right) => left.stringify().compare(right.stringify()))
    inspect(
      results.map(value => value.stringify()).join("|"),
      content="{\"call\":1}|{\"call\":2}",
    )
  })
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
