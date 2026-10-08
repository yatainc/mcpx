///|
test "mcp client sse: decodes data events and multiline payloads" {
  let text =
    #|event: message
    #|data: line1
    #|data: line2
    #|
    #|: keepalive
    #|data: {"jsonrpc":"2.0","id":2,"result":{"ok":true}}
    #|
  @debug.debug_inspect(
    decode_sse_data(text),
    content=(
      #|[
      #|  "line1\nline2",
      #|  "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"ok\":true}}",
      #|]
    ),
  )
}
