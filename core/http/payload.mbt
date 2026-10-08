///|
pub enum Payload {
  JsonPayload(Json)
  AcceptedNoContent
} derive(Debug)

///|
pub fn decode_payload(
  response : HttpResponse,
) -> Payload raise @protocol.McpProtocolError {
  if response.status_code == 202 {
    return AcceptedNoContent
  }
  if response.status_code != 200 {
    raise InvalidResponse("unexpected transport status")
  }
  let content_type = response.content_type.unwrap_or_default().to_lower()
  if content_type.contains("text/event-stream") {
    let payload = match decode_sse_data(response.body).get(0) {
      Some(value) => value
      None => raise InvalidResponse("missing sse data")
    }
    JsonPayload(
      @json.parse(payload) catch {
        _ => raise InvalidResponse("invalid sse json")
      },
    )
  } else {
    JsonPayload(
      @json.parse(response.body) catch {
        _ => raise InvalidResponse("invalid json body")
      },
    )
  }
}

///|
pub fn expect_json(payload : Payload) -> Json raise @protocol.McpProtocolError {
  match payload {
    JsonPayload(json) => json
    AcceptedNoContent => raise InvalidResponse("expected json payload")
  }
}
