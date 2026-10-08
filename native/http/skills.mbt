///|
pub async fn http_mcp_list_skills(
  url~ : String,
  headers~ : Map[String, String],
) -> Array[Json] raise @core_http.McpHttpClientError {
  @core_http.list_skills(
    native_fetch,
    @core_http.http_endpoint(url~, headers~, mode=Stateless),
  )
}

///|
pub async fn http_mcp_get_skill(
  url~ : String,
  headers~ : Map[String, String],
  uri~ : String,
) -> Json raise @core_http.McpHttpClientError {
  @core_http.get_skill(
    native_fetch,
    @core_http.http_endpoint(url~, headers~, mode=Stateless),
    uri~,
  )
}

///|
pub async fn http_mcp_read_resource(
  url~ : String,
  headers~ : Map[String, String],
  uri~ : String,
) -> @skills.ReadResult raise @core_http.McpHttpClientError {
  @core_http.read_resource(
    native_fetch,
    @core_http.http_endpoint(url~, headers~, mode=Stateless),
    uri~,
  )
}
