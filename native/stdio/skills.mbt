///|
fn StdioMcpClient::resource_capabilities(
  self : StdioMcpClient,
) -> Json raise McpStdioError {
  match self.lifecycle {
    Stateless(capabilities) => capabilities
    Initialize => raise Protocol("retrieval requires MCP 2026-07-28")
  }
}

///|
pub async fn StdioMcpClient::list_skills(
  self : StdioMcpClient,
) -> Array[Json] raise McpStdioError {
  self.with_operation(() => {
    @skills.list(
      (rpc, params) => self.request(rpc, params),
      capabilities=self.resource_capabilities(),
    )
  })
}

///|
pub async fn StdioMcpClient::get_skill(
  self : StdioMcpClient,
  uri~ : String,
) -> Json raise McpStdioError {
  self.with_operation(() => {
    @skills.get(
      (rpc, params) => self.request(rpc, params),
      capabilities=self.resource_capabilities(),
      uri~,
    )
  })
}

///|
pub async fn StdioMcpClient::read_resource(
  self : StdioMcpClient,
  uri~ : String,
) -> @skills.ReadResult raise McpStdioError {
  self.with_operation(() => {
    @skills.read(
      (rpc, params) => self.request(rpc, params),
      capabilities=self.resource_capabilities(),
      uri~,
    )
  })
}
