///|
async fn native_fetch(
  request : @core_http.HttpRequest,
) -> @core_http.HttpResponse {
  let (response, data) = @async_http.post(
    request.url,
    request.body,
    headers=Map::from_iter(
      request.headers
      .iter()
      .map(header => {
        let (name, value) = header
        (CaseInsensitiveString(name), value)
      }),
    ),
  )
  let content_type = response.headers.get("content-type")
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
    headers=Map::from_iter(
      response.headers
      .iter()
      .map(header => {
        let (name, value) = header
        (name.to_string(), value)
      }),
    ),
    body~,
  )
}
