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
pub extend McpHttpClientError with Debug::{to_repr}
