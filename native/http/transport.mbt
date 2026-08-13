///|
async fn native_fetch(
  request : @core_http.HttpRequest,
) -> @core_http.HttpResponse {
  let (response, data) = @async_http.post(
    request.url,
    request.body,
    headers=request.headers,
  )
  let content_type = header(response.headers, "content-type")
  let body = if response.code == 202 {
    ""
  } else {
    data.text() catch {
      _ => ""
    }
  }
  @core_http.http_response(
    status_code=response.code,
    content_type~,
    headers=response.headers,
    body~,
  )
}

///|
fn header(headers : Map[String, String], key : String) -> String? {
  for name, value in headers {
    if name.equal_ignore_ascii_case(key) {
      return Some(value)
    }
  }
  None
}
