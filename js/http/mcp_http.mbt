///|
#external
pub type JsFetch

///|
extern "js" fn call_js_fetch(
  fetch : JsFetch,
  http_method : String,
  url : String,
  headers_json : String,
  body : String,
) -> @js_async.Promise[String] =
  #| (fetch, httpMethod, url, headersJson, body) => fetch(httpMethod, url, headersJson, body)

///|
pub async fn list_tools_js(
  fetch : JsFetch,
  url~ : String,
) -> Array[@protocol.McpToolInfo] {
  @core_http.list_tools(js_fetch_adapter(fetch), @core_http.http_endpoint(url~))
}

///|
pub async fn call_tool_js(
  fetch : JsFetch,
  url~ : String,
  tool_name~ : String,
  arguments~ : Json,
) -> Json {
  @core_http.call_tool(
    js_fetch_adapter(fetch),
    @core_http.http_endpoint(url~),
    tool_name~,
    arguments~,
  )
}

///|
fn js_fetch_adapter(
  fetch : JsFetch,
) -> async (@core_http.HttpRequest) -> @core_http.HttpResponse {
  request => {
    let result_json = call_js_fetch(
      fetch,
      request.http_method,
      request.url,
      string_map_to_json(request.headers).stringify(),
      request.body,
    ).wait()
    decode_js_http_response(result_json)
  }
}

///|
pub fn mcpx_js_list_tools(
  fetch : JsFetch,
  url : String,
) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(() => {
    let tools = list_tools_js(fetch, url~)
    let arr = tools.map(tool_info_json)
    Json::object({ "status": Json::string("ok"), "tools": Json::array(arr) }).stringify()
  })
}

///|
pub fn mcpx_js_call_tool(
  fetch : JsFetch,
  url : String,
  tool_name : String,
  arguments_json : String,
) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(() => {
    let arguments = @json.parse(arguments_json) catch {
      _ => Json::empty_object()
    }
    let result = call_tool_js(fetch, url~, tool_name~, arguments~)
    Json::object({ "status": Json::string("ok"), "result": result }).stringify()
  })
}

///|
fn decode_js_http_response(text : String) -> @core_http.HttpResponse {
  let json = @json.parse(text) catch {
    _ => return @core_http.http_response(status_code=599, body=text)
  }
  let obj = match json {
    Object(obj) => obj
    _ => return @core_http.http_response(status_code=599, body=text)
  }
  let status_code = int_field(obj, "statusCode").unwrap_or(599)
  let content_type = string_field(obj, "contentType")
  let body = string_field(obj, "body").unwrap_or("")
  let headers = match obj.get("headers") {
    Some(Object(values)) => json_string_map(values)
    _ => Map([])
  }
  @core_http.http_response(status_code~, content_type~, headers~, body~)
}

///|
fn int_field(obj : Map[String, Json], key : String) -> Int? {
  match obj.get(key) {
    Some(Number(value, ..)) if value.trunc() == value => Some(value.to_int())
    _ => None
  }
}

///|
fn string_field(obj : Map[String, Json], key : String) -> String? {
  match obj.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn json_string_map(obj : Map[String, Json]) -> Map[String, String] {
  let out : Map[String, String] = Map([])
  for key, value in obj {
    match value {
      String(text) => out[key] = text
      _ => ()
    }
  }
  out
}

///|
fn string_map_to_json(values : Map[String, String]) -> Json {
  let obj : Map[String, Json] = Map([])
  for key, value in values {
    obj[key] = Json::string(value)
  }
  Json::object(obj)
}

///|
fn tool_info_json(tool : @protocol.McpToolInfo) -> Json {
  let obj : Map[String, Json] = Map([])
  obj["name"] = Json::string(tool.name)
  match tool.description {
    Some(description) => obj["description"] = Json::string(description)
    None => ()
  }
  obj["inputSchema"] = tool.input_schema
  match tool.output_schema {
    Some(value) => obj["outputSchema"] = value
    None => ()
  }
  Json::object(obj)
}
