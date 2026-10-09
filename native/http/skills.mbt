///|
/// A reusable fixed peer. Supply a shared budget only for one finite operation.
pub async fn http_mcp_skill_source(
  url~ : String,
  headers~ : Map[String, String],
  origin~ : String,
  budget? : @receive.Budget,
  timeout_ms? : Int = 30000,
) -> @skills.Source {
  @core_http.skill_source(
    request => {
      let budget = match budget {
        Some(budget) => budget
        None => @receive.Budget::new()
      }
      @async.with_timeout(timeout_ms, () => bounded_fetch(request, budget))
    },
    @core_http.http_endpoint(url~, headers~, mode=Stateless),
    origin,
  )
}

///|
pub async fn http_mcp_list_skills(
  url~ : String,
  headers~ : Map[String, String],
) -> Array[Json] {
  let budget = @receive.Budget::new()
  @core_http.list_skills(
    request => bounded_fetch(request, budget),
    @core_http.http_endpoint(url~, headers~, mode=Stateless),
  )
}

///|
pub async fn http_mcp_get_skill(
  url~ : String,
  headers~ : Map[String, String],
  uri~ : String,
) -> Json {
  let budget = @receive.Budget::new()
  @core_http.get_skill(
    request => bounded_fetch(request, budget),
    @core_http.http_endpoint(url~, headers~, mode=Stateless),
    uri~,
  )
}

///|
pub async fn http_mcp_read_resource(
  url~ : String,
  headers~ : Map[String, String],
  uri~ : String,
) -> @skills.ReadResult {
  let budget = @receive.Budget::new()
  @core_http.read_resource(
    request => bounded_fetch(request, budget),
    @core_http.http_endpoint(url~, headers~, mode=Stateless),
    uri~,
  )
}

///|
// Retrieval-only transport. Tool HTTP retains its existing transport behavior.
async fn bounded_fetch(
  request : @core_http.HttpRequest,
  budget : @receive.Budget,
) -> @core_http.HttpResponse {
  let headers : Map[@async_http.CaseInsensitiveString, String] = Map::from_iter(
    request.headers
    .iter()
    .map(header => {
      let (name, value) = header
      (CaseInsensitiveString(name), value)
    }),
  )
  let client = @async_http.post_stream(request.url, headers~)
  defer client.close()
  client.write(request.body)
  let response = client.end_request()
  let body = if response.code != 200 &&
    response.code != 400 &&
    response.code != 404 {
    ""
  } else {
    @utf8.decode(@receive.body(client, budget))
  }
  @core_http.http_response(
    status_code=response.code,
    content_type=response.headers.get("content-type"),
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
