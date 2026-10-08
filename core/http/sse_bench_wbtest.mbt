///|
test "bench MCP SSE decode ten events" (it : @bench.T) {
  let events = []
  for id in 1..<=10 {
    events.push(
      "event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":" +
      id.to_string() +
      ",\"result\":{\"ok\":true}}\n\n",
    )
  }
  let payload = events.join("")
  it.bench(() => it.keep(decode_sse_data(payload).length()))
}
