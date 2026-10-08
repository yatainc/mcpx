///|
pub enum Payload {
  JsonPayload(Json)
  AcceptedNoContent
} derive(Debug)

///|
pub extend Payload with Debug::{to_repr}

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
    for data in decode_sse_data(response.body) {
      let json = @json.parse(data) catch {
        _ => raise InvalidResponse("invalid sse json")
      }
      // Request-related notifications may precede the response.
      if json
        is {
          "jsonrpc": "2.0",
          "method": String(_),
          "id"? : None,
          "result"? : None,
          "error"? : None,
          ..
        } {
        continue
      }
      return JsonPayload(json)
    }
    raise InvalidResponse("missing sse response")
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
