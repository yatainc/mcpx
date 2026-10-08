///|
priv struct ModernHttp {
  fetch : async (HttpRequest) -> HttpResponse
  endpoint : Endpoint
  version : @protocol.McpProtocolVersion
  mut next_id : Int
}

///|
fn modern_http(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  version : @protocol.McpProtocolVersion,
) -> ModernHttp {
  { fetch, endpoint, version, next_id: 2 }
}

///|
async fn ModernHttp::request(
  self : ModernHttp,
  rpc_method : String,
  params : Map[String, Json],
  name? : String? = None,
  parameter_values? : Map[String, String] = Map([]),
) -> Json {
  let id = self.next_id
  self.next_id += 1
  let context = @protocol.mcp_request_context(
    protocol=self.version,
    client_name=@protocol.MCPX_CLIENT_NAME,
    client_version=@protocol.MCPX_CLIENT_VERSION,
  )
  let headers = build_modern_headers(
    self.endpoint.headers,
    self.version,
    rpc_method,
    name,
  )
  for key, value in parameter_values {
    set_header_case_insensitive(
      headers,
      "Mcp-Param-" + key,
      encode_mcp_http_header_value(value),
    )
  }
  let response = post_json(
    self.fetch,
    self.endpoint,
    headers,
    @protocol.mcp_request(
      id,
      rpc_method,
      Some(@protocol.with_mcp_request_meta(params, context)),
    ),
  )
  @protocol.decode_mcp_result(
    response_json(response, expected_id=id),
    expected_id=id,
  )
}
