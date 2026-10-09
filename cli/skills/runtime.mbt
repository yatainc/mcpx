///|
pub async fn run_http(
  command : Command,
  url~ : String,
  headers~ : Map[String, String],
  timeout_ms? : Int = 30000,
) -> String {
  @async.with_timeout(timeout_ms, () => {
    match command.operation {
      List =>
        render_skill_pages(
          @mcp_http.http_mcp_list_skills(url~, headers~),
          origin(command.target),
          command.json_output,
        )
      Get(uri) =>
        render_skill_result(
          origin(command.target),
          @mcp_http.http_mcp_get_skill(url~, headers~, uri~),
        )
      Verify(uri) => {
        let source = @mcp_http.http_mcp_skill_source(
          url~,
          headers~,
          origin=origin(command.target),
          budget=@receive.Budget::new(),
          timeout_ms~,
        )
        let held = source.hold(uri)
        render_verified(held, held.read(uri), command.json_output)
      }
      Read(uri) =>
        render_resource(
          @mcp_http.http_mcp_read_resource(url~, headers~, uri~),
          command.json_output,
        )
    }
  }) catch {
    @core_http.HttpStatus(401 | 403) =>
      raise RetrievalError(
        if command.target == url {
          "authentication required; use a configured server with credentials"
        } else {
          "authentication required; run mcpx auth " + command.target
        },
      )
    @core_http.HttpStatus(code) =>
      raise RetrievalError("HTTP " + code.to_string())
    @core_http.Protocol(message) | @core_http.RemoteError(_, message) =>
      raise RetrievalError(message)
    error => raise error
  }
}

///|
pub async fn run_stdio(
  command : Command,
  server : @config.McpServerConfig,
  timeout_ms? : Int = 30000,
) -> String {
  guard server.command is Some(executable) else {
    raise RetrievalError("server has no command: " + command.target)
  }
  @async.with_timeout(timeout_ms, () => {
    @async.with_task_group(group => {
      let client = @mcp_stdio.stdio_mcp_connect(
        group,
        command=executable,
        args=server.args,
        env=server.env,
        cwd=server.cwd,
        mode=Stateless,
        probe_timeout_ms=timeout_ms,
        response_timeout_ms=timeout_ms,
        receive_budget=@receive.Budget::new(),
      )
      defer client.close()
      match command.operation {
        List =>
          render_skill_pages(
            client.list_skills(),
            origin(command.target),
            command.json_output,
          )
        Get(uri) =>
          render_skill_result(origin(command.target), client.get_skill(uri~))
        Verify(uri) => {
          let held = client.skill_source(origin(command.target)).hold(uri)
          render_verified(held, held.read(uri), command.json_output)
        }
        Read(uri) =>
          render_resource(client.read_resource(uri~), command.json_output)
      }
    })
  }) catch {
    @mcp_stdio.Protocol(message) => raise RetrievalError(message)
    error => raise error
  }
}
