///|
test "mcp client transport model: normalizes json sse and accepted payloads" {
  let json_response = @http.http_response(
    status_code=200,
    content_type=Some("application/json"),
    body="{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}",
  )
  json_inspect(@http.expect_json(@http.decode_payload(json_response)), content={
    "jsonrpc": "2.0",
    "id": 1,
    "result": {},
  })
  let sse_response = @http.http_response(
    status_code=200,
    content_type=Some("text/event-stream"),
    body="data: {\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"ok\":true}}\n\n",
  )
  json_inspect(@http.expect_json(@http.decode_payload(sse_response)), content={
    "jsonrpc": "2.0",
    "id": 2,
    "result": { "ok": true },
  })
  inspect(
    @http.decode_payload(@http.http_response(status_code=202, body=""))
    is AcceptedNoContent,
    content="true",
  )
}
