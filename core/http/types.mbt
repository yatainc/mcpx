///|
pub struct HttpRequest {
  http_method : String
  url : String
  headers : Map[String, String]
  body : String
}

///|
pub struct HttpResponse {
  status_code : Int
  content_type : String?
  headers : Map[String, String]
  body : String
}

///|
pub struct Endpoint {
  url : String
  headers : Map[String, String]
  mode : @config.McpConnectionMode
}

///|
pub fn http_endpoint(
  url~ : String,
  headers? : Map[String, String] = Map([]),
  mode? : @config.McpConnectionMode = Auto,
) -> Endpoint {
  { url, headers, mode }
}

///|
pub fn http_response(
  status_code~ : Int,
  content_type? : String? = None,
  headers? : Map[String, String] = Map([]),
  body~ : String,
) -> HttpResponse {
  { status_code, content_type, headers, body }
}
