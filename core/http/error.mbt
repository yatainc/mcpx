///|
#derive(Debug)
pub suberror McpHttpClientError {
  HttpStatus(Int32)
  Network(String)
  Protocol(String)
  HeaderMismatch(String)
  MissingRequiredClientCapability(String)
  UnsupportedProtocolVersion(Array[String])
  ModeProtocolIncompatible(String, String)
  RemoteError(Int32, String)
}

///|
pub extend McpHttpClientError with Debug::{to_repr}
