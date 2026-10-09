///|
#cfg(all(target="native", not(platform="windows")))
async test "stdio CLI retrieval uses modern discovery, paginates and falls back on the same process" {
  let script =
    #|i=0
    #|while IFS= read -r line; do
    #|  i=$((i + 1))
    #|  case "$line" in *'io.modelcontextprotocol/clientInfo'*) ;; *) exit 1 ;; esac
    #|  case "$line" in
    #|    *'"method":"server/discover"'*)
    #|      result='{"resultType":"complete","supportedVersions":["2026-07-28"],"capabilities":{"resources":{},"extensions":{"io.modelcontextprotocol/skills":{"directoryRead":true}}}}' ;;
    #|    *'"method":"skills/get"'*)
    #|      result='{"resultType":"complete","skill":{"uri":"opaque://demo/SKILL.md","frontmatter":{"name":"demo","description":"Demo"},"resources":"dynamic"},"ttlMs":0,"cacheScope":"public","extra":true}' ;;
    #|    *'"method":"skills/list"'*)
    #|      if [ "$i" = 2 ]; then
    #|        result='{"resultType":"complete","skills":[],"nextCursor":"","ttlMs":0,"cacheScope":"public"}'
    #|      else
    #|        case "$line" in *'"cursor":""'*) ;; *) exit 1 ;; esac
    #|        result='{"resultType":"complete","skills":[],"ttlMs":0,"cacheScope":"public"}'
    #|      fi ;;
    #|    *'"method":"resources/directory/read"'*)
    #|      printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32602,"message":"file"}}\n' "$i"
    #|      continue ;;
    #|    *'"method":"resources/read"'*)
    #|      if [ "$i" != 3 ]; then exit 1; fi
    #|      result='{"resultType":"complete","contents":[{"uri":"opaque://file","text":"Error: ordinary data"},{"uri":"opaque://blob","blob":"AAE="}],"ttlMs":0,"cacheScope":"private","status":"error"}' ;;
    #|    *) exit 1 ;;
    #|  esac
    #|  printf '{"jsonrpc":"2.0","id":%s,"result":%s}\n' "$i" "$result"
    #|done
  let server = @config.mcp_server_config(
    name="srv",
    transport=Stdio,
    command=Some("/bin/sh"),
    args=["-c", script],
  )
  let pages = @skills.run_stdio(
    { target: "srv", operation: List, json_output: true, },
    server,
  )
  assert_true(
    @json.parse(pages)
    is { "origin": "config:srv", "result": { "pages": [_, _], .. }, .. },
  )
  let entry = @skills.run_stdio(
    {
      target: "srv",
      operation: Get("opaque://demo/SKILL.md"),
      json_output: true,
    },
    server,
  )
  assert_true(
    @json.parse(entry)
    is { "origin": "config:srv", "result": { "extra": True, .. }, .. },
  )
  let result = @skills.run_stdio(
    { target: "srv", operation: Read("opaque://file"), json_output: true, },
    server,
  )
  assert_true(
    @json.parse(result) is { "status": "error", "contents": [_, _], .. },
  )
  let text = @skills.run_stdio(
    { target: "srv", operation: Read("opaque://file"), json_output: false, },
    server,
  )
  assert_true(text.has_prefix("Error: ordinary data\n"))
  assert_true(text.contains("AAE="))
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "stdio command deadline includes discovery and all list pages" {
  let script =
    #|i=0
    #|while IFS= read -r line; do
    #|  i=$((i + 1))
    #|  sleep 0.6
    #|  if [ "$i" = 1 ]; then
    #|    result='{"resultType":"complete","supportedVersions":["2026-07-28"],"capabilities":{"resources":{},"extensions":{"io.modelcontextprotocol/skills":{}}}}'
    #|  elif [ "$i" = 2 ]; then
    #|    result='{"resultType":"complete","skills":[],"nextCursor":"next","ttlMs":0,"cacheScope":"public"}'
    #|  else
    #|    result='{"resultType":"complete","skills":[],"ttlMs":0,"cacheScope":"public"}'
    #|  fi
    #|  printf '{"jsonrpc":"2.0","id":%s,"result":%s}\n' "$i" "$result"
    #|done
  let server = @config.mcp_server_config(
    name="srv",
    transport=Stdio,
    command=Some("/bin/sh"),
    args=["-c", script],
  )
  @async.with_timeout(6000, () => {
    try
      @skills.run_stdio(
        { target: "srv", operation: List, json_output: true, },
        server,
        timeout_ms=1600,
      )
    catch {
      @async.TimeoutError => ()
      error => fail("wrong timeout: \{error}")
    } noraise {
      _ => fail("deadline reset after discovery")
    }
  })
}
