///|
async test "mcpx runtime: search finds servers by description" {
  let home = "/tmp/mcpx-runtime-search-desc-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.servers_config) catch {
    _ => ()
  }
  @storage.save_mcpx_config_file(
    paths.servers_config,
    @config.put_server_config(
      @config.put_server_config(
        @config.empty_mcpx_config(),
        @config.mcp_server_config(
          name="github",
          transport=Http,
          url=Some("https://mcp.github.com/mcp"),
          description=Some("GitHub Issues, PRs, and code search"),
        ),
      ),
      @config.mcp_server_config(
        name="playwright",
        transport=Stdio,
        command=Some("npx"),
        args=["@playwright/mcp"],
        description=Some("Browser automation"),
      ),
    ),
  )
  let result = run_mcpx_args_async(["search", "git"], home~)
  inspect(result.contains("github:"), content="true")
  inspect(result.contains("GitHub Issues"), content="true")
  inspect(!result.contains("playwright"), content="true")
  inspect(result.contains("1 match"), content="true")
}

///|
async test "mcpx runtime: search shows no description when missing" {
  let home = "/tmp/mcpx-runtime-search-nodesc-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.servers_config) catch {
    _ => ()
  }
  @storage.save_mcpx_config_file(
    paths.servers_config,
    @config.put_server_config(
      @config.empty_mcpx_config(),
      @config.mcp_server_config(
        name="local-tools",
        transport=Stdio,
        command=Some("/bin/sh"),
      ),
    ),
  )
  let result = run_mcpx_args_async(["search", "local"], home~)
  inspect(result.contains("local-tools:"), content="true")
  inspect(result.contains("(no description)"), content="true")
}

///|
async test "mcpx runtime: search no match message" {
  let home = "/tmp/mcpx-runtime-search-nomatch-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.servers_config) catch {
    _ => ()
  }
  @storage.save_mcpx_config_file(
    paths.servers_config,
    @config.put_server_config(
      @config.empty_mcpx_config(),
      @config.mcp_server_config(
        name="github",
        transport=Http,
        url=Some("https://mcp.github.com/mcp"),
        description=Some("GitHub Issues"),
      ),
    ),
  )
  let result = run_mcpx_args_async(["search", "nonexistent"], home~)
  inspect(result.contains("No servers matched"), content="true")
}

///|
async test "mcpx runtime: search sorts by relevance" {
  let home = "/tmp/mcpx-runtime-search-sort-test/home"
  let paths = @app_paths.mcpx_app_paths(home)
  @fs.remove_file(paths.servers_config) catch {
    _ => ()
  }
  @storage.save_mcpx_config_file(
    paths.servers_config,
    @config.put_server_config(
      @config.put_server_config(
        @config.put_server_config(
          @config.empty_mcpx_config(),
          @config.mcp_server_config(
            name="gitlab",
            transport=Http,
            url=Some("https://gitlab.com/mcp"),
            description=Some("GitLab code review"),
          ),
        ),
        @config.mcp_server_config(
          name="github",
          transport=Http,
          url=Some("https://mcp.github.com/mcp"),
          description=Some("GitHub Issues and PRs"),
        ),
      ),
      @config.mcp_server_config(
        name="playwright",
        transport=Stdio,
        command=Some("npx"),
        args=["@playwright/mcp"],
        description=Some("Browser automation"),
      ),
    ),
  )
  let result = run_mcpx_args_async(["search", "git"], home~)
  let lines = result.split("\n").iter().to_array()
  // github has exact name match → highest score, appears first
  // gitlab has prefix match → second
  // playwright not matched → excluded
  inspect(lines[0].has_prefix("github:"), content="true")
  inspect(lines[1].has_prefix("gitlab:"), content="true")
  inspect(!result.contains("playwright"), content="true")
  inspect(result.contains("2 matches"), content="true")
}
