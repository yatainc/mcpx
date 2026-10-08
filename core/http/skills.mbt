///|
async fn[T] with_resources(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  operation : async (ModernHttp) -> T,
) -> T raise McpHttpClientError {
  with_http_errors(() => {
    if endpoint.mode == Stateful {
      raise ModeProtocolIncompatible("stateful", "2026-07-28")
    }
    let endpoint = http_endpoint(
      url=endpoint.url,
      headers=endpoint.headers,
      mode=Stateless,
    )
    match negotiate(fetch, endpoint) {
      Modern(version, capabilities) =>
        operation(modern_http(fetch, endpoint, version, capabilities))
      InitializeEra(_) => raise Protocol("retrieval requires MCP 2026-07-28")
    }
  })
}

///|
pub async fn list_skills(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
) -> Array[Json] raise McpHttpClientError {
  with_resources(fetch, endpoint, connection => {
    @skills.list(
      (rpc, params) => connection.request(rpc, params),
      capabilities=connection.capabilities,
    )
  })
}

///|
pub async fn get_skill(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  uri~ : String,
) -> Json raise McpHttpClientError {
  with_resources(fetch, endpoint, connection => {
    @skills.get(
      (rpc, params) => connection.request(rpc, params),
      capabilities=connection.capabilities,
      uri~,
    )
  })
}

///|
pub async fn read_resource(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  uri~ : String,
) -> @skills.ReadResult raise McpHttpClientError {
  with_resources(fetch, endpoint, connection => {
    @skills.read(
      (rpc, params) => connection.request(rpc, params),
      capabilities=connection.capabilities,
      uri~,
    )
  })
}
