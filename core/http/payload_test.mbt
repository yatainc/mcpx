///|
test "mcp client transport model: normalizes json sse and accepted payloads" {
  let json_response = http_response(
    status_code=200,
    content_type=Some("application/json"),
    body="{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}",
  )
  json_inspect(expect_json(decode_payload(json_response)), content={
    "jsonrpc": "2.0",
    "id": 1,
    "result": {},
  })
  let sse_response = http_response(
    status_code=200,
    content_type=Some("text/event-stream"),
    body="data: {\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"ok\":true}}\n\n",
  )
  json_inspect(expect_json(decode_payload(sse_response)), content={
    "jsonrpc": "2.0",
    "id": 2,
    "result": { "ok": true },
  })
  inspect(
    decode_payload(http_response(status_code=202, body="")) is AcceptedNoContent,
    content="true",
  )
}
