///|
test "HTTP response: decodes successful JSON payloads" {
  let json = response_json(
    http_response(
      status_code=200,
      content_type=Some("application/json"),
      body=(
        #|{"jsonrpc":"2.0","id":7,"result":{"ok":true}}
      ),
    ),
    expected_id=7,
  )
  inspect(
    json.stringify(),
    content="{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":{\"ok\":true}}",
  )
}

///|
test "HTTP response: accepts empty 202 transport payloads" {
  let payload = response_payload(http_response(status_code=202, body=""))
  inspect(payload is AcceptedNoContent, content="true")
}

///|
test "HTTP response: preserves valid remote errors on non-success status" {
  try
    response_json(
      http_response(
        status_code=400,
        content_type=Some("application/json"),
        body=(
          #|{"jsonrpc":"2.0","id":3,"error":{"code":-32602,"message":"bad params"}}
        ),
      ),
      expected_id=3,
    )
  catch {
    RemoteError(code, message) => {
      inspect(code, content="-32602")
      inspect(message, content="bad params")
    }
    _ => fail("expected remote error")
  } noraise {
    _ => fail("expected response failure")
  }
}

///|
test "HTTP response: rejects malformed non-success bodies as status errors" {
  try response_json(http_response(status_code=503, body="unavailable")) catch {
    HttpStatus(code) => inspect(code, content="503")
    _ => fail("expected HTTP status error")
  } noraise {
    _ => fail("expected response failure")
  }
}
