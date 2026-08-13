///|
pub suberror McpHttpClientError {
  HttpStatus(Int)
  Network(String)
  Protocol(String)
  HeaderMismatch(String)
  MissingRequiredClientCapability(String)
  UnsupportedProtocolVersion(Array[String])
  ModeProtocolIncompatible(String, String)
  RemoteError(Int, String)
} derive(Debug)

///|
pub fn mcp_http_client_status_code(error : McpHttpClientError) -> Int? {
  match error {
    HttpStatus(code) => Some(code)
    _ => None
  }
}
