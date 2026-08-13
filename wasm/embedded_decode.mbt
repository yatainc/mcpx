///|
suberror EmbeddedError {
  ExpectedObject
  ExpectedString(String)
} derive(Debug)

///|
fn expect_object(json : Json) -> Map[String, Json] raise EmbeddedError {
  match json {
    Object(obj) => obj
    _ => raise ExpectedObject
  }
}

///|
fn expect_string_field(
  obj : Map[String, Json],
  field : String,
) -> String raise EmbeddedError {
  match obj.get(field) {
    Some(String(value)) => value
    _ => raise ExpectedString(field)
  }
}

///|
fn expect_bool_field(
  obj : Map[String, Json],
  field : String,
) -> Bool raise EmbeddedError {
  match obj.get(field) {
    Some(True) => true
    Some(False) => false
    _ => raise ExpectedString(field)
  }
}

///|
fn expect_int_field(
  obj : Map[String, Json],
  field : String,
) -> Int raise EmbeddedError {
  match obj.get(field) {
    Some(Number(value, ..)) if value.trunc() == value => value.to_int()
    _ => raise ExpectedString(field)
  }
}

///|
fn optional_string_field(obj : Map[String, Json], field : String) -> String? {
  match obj.get(field) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn parse_host_result(
  host_result_json : String,
) -> Map[String, Json] raise EmbeddedError {
  let host_result = @json.parse(host_result_json) catch {
    _ => raise ExpectedObject
  }
  expect_object(host_result)
}

///|
fn mcp_host_result_json(host_result_json : String) -> Json raise EmbeddedError {
  let host_result_obj = parse_host_result(host_result_json)
  let ok = expect_bool_field(host_result_obj, "ok")
  if !ok {
    raise ExpectedObject
  }
  let status_code = expect_int_field(host_result_obj, "statusCode")
  let content_type = optional_string_field(host_result_obj, "contentType")
  let body = expect_string_field(host_result_obj, "body")
  let payload = match
    @mcp_client.decode_mcp_transport_payload(
      @mcp_client.mcp_transport_response(status_code~, content_type~, body~),
    ) {
    Ok(value) => value
    Err(_) => raise ExpectedObject
  }
  @mcp_client.expect_json_payload(payload) catch {
    _ => raise ExpectedObject
  }
}

///|
fn optional_int_field(
  obj : Map[String, Json],
  field : String,
  default~ : Int,
) -> Int {
  match obj.get(field) {
    Some(Number(value, ..)) if value.trunc() == value => value.to_int()
    _ => default
  }
}

///|
fn ready(authorization_header : String) -> String {
  let obj = Map([])
  obj["status"] = Json::string("ready")
  let headers = Map([])
  headers["Authorization"] = Json::string(authorization_header)
  obj["headers"] = Json::object(headers)
  Json::object(obj).stringify()
}

///|
fn refresh_required(refresh_token : String) -> String {
  let obj = Map([])
  obj["status"] = Json::string("refresh_required")
  obj["refreshToken"] = Json::string(refresh_token)
  Json::object(obj).stringify()
}

///|
fn reauth_required(server_name : String) -> String {
  let obj = Map([])
  obj["status"] = Json::string("reauth_required")
  obj["command"] = Json::string("mcpx auth " + server_name)
  obj["noBrowser"] = Json::boolean(true)
  Json::object(obj).stringify()
}

///|
fn wasm_error(code : String, message : String) -> String {
  let obj = Map([])
  obj["status"] = Json::string("error")
  obj["code"] = Json::string(code)
  obj["message"] = Json::string(message)
  Json::object(obj).stringify()
}

///|
fn json_int(value : Int) -> Json {
  Json::number(Double::from_int(value), repr=value.to_string())
}
