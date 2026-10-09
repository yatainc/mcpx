///|
/// Fixed origin and peer; callback reuses the client's existing operation lock.
pub fn StdioMcpClient::skill_source(
  self : StdioMcpClient,
  origin : String,
) -> @skills.Source raise {
  let capabilities = self.resource_capabilities()
  @skills.Source::new(origin, capabilities~, call=(rpc, params) => {
    self.with_operation(() => self.request(rpc, params))
  })
}

///|
fn StdioMcpClient::resource_capabilities(
  self : StdioMcpClient,
) -> Json raise McpStdioError {
  match self.lifecycle {
    Stateless(capabilities) => {
      if self.conn.lines is None {
        self.conn.lines = Some(@receive.Lines::new(self.conn.reader))
      }
      capabilities
    }
    Initialize => raise Protocol("retrieval requires MCP 2026-07-28")
  }
}

///|
pub async fn StdioMcpClient::list_skills(
  self : StdioMcpClient,
) -> Array[Json] raise McpStdioError {
  let capabilities = self.resource_capabilities()
  self.with_operation(() => {
    @skills.list((rpc, params) => self.request(rpc, params), capabilities~)
  })
}

///|
pub async fn StdioMcpClient::get_skill(
  self : StdioMcpClient,
  uri~ : String,
) -> Json raise McpStdioError {
  let capabilities = self.resource_capabilities()
  self.with_operation(() => {
    @skills.get((rpc, params) => self.request(rpc, params), capabilities~, uri~)
  })
}

///|
pub async fn StdioMcpClient::read_resource(
  self : StdioMcpClient,
  uri~ : String,
) -> @skills.ReadResult raise McpStdioError {
  let capabilities = self.resource_capabilities()
  self.with_operation(() => {
    @skills.read(
      (rpc, params) => self.request(rpc, params),
      capabilities~,
      uri~,
    )
  })
}
