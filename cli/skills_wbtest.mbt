///|
// Existing CLI tests exercise argv-to-text behavior. Production parses once
// in main and keeps success/failure separate from the returned resource text.
async fn execute_mcpx(
  args : Array[String],
  home~ : String,
  config_home? : String? = None,
  stdin_json? : String? = None,
) -> String {
  let command = match parse_mcpx_args(args) {
    Ok(command) => command
    Err(error) => return error_result(format_mcpx_parse_error(error))
  }
  match execute_command(command, home~, config_home~, stdin_json~) {
    Ok(text) | Err(text) => text
  }
}

///|
test "retrieval arguments are positional, with no legacy verbs or flags" {
  for target in ["list", "get", "read", "https://example.test/mcp"] {
    guard parse_mcpx_args(["skills", target, "--json"])
      is Ok(Retrieve({ target: parsed, operation: List, json_output: true, })) else {
      fail("expected list")
    }
    assert_eq(parsed, target)
    guard parse_mcpx_args(["skills", target, "opaque://a/SKILL.md"])
      is Ok(Retrieve({ operation: Get("opaque://a/SKILL.md"), .. })) else {
      fail("expected direct get")
    }
    guard parse_mcpx_args(["resources", target, "opaque://a", "--json"])
      is Ok(Retrieve({ operation: Read("opaque://a"), json_output: true, .. })) else {
      fail("expected resource read")
    }
  }
  for
    args in [
      ["resources", "server"],
      ["skills", "server", "--cursor", "a"],
      ["resources", "server", "uri", "--directory"],
      ["skills", "server", "a", "b"],
      ["skills", "server", "--json", "--json"],
      ["skills", "server", "--verify"],
      ["skills", "server", "uri", "--verify", "--verify"],
      ["resources", "server", "uri", "--verify"],
      ["skills", "server", "uri", "--file", "file"],
    ] {
    assert_true(parse_mcpx_args(args) is Err(_))
  }
  assert_true(
    parse_mcpx_args(["skills", "server", "uri", "--verify", "--json"])
    is Ok(Retrieve({ operation: Verify("uri"), json_output: true, .. })),
  )
  assert_true(parse_mcpx_args(["skills"]) is Ok(SkillsHelp))
  assert_true(parse_mcpx_args(["resources", "--help"]) is Ok(ResourcesHelp))
}

///|
async test "retrieval admission rejects stateful and keep-alive before launch or env resolution" {
  let home = "/tmp/mcpx-retrieval-admission-" + @env.now().to_string()
  let paths = @app_paths.mcpx_app_paths(home)
  defer (@fs.remove_file(paths.servers_config) catch { _ => () })
  for stateful in [true, false] {
    let server = @config.mcp_server_config(
      name="srv",
      transport=Stdio,
      command=Some("/must/not/spawn"),
      env={ "CHECK": "${MCPX_RETRIEVAL_UNSET}" },
      protocol_mode=if stateful { Some(Stateful) } else { None },
      lifecycle=if stateful {
        None
      } else {
        Some(@config.server_lifecycle(KeepAlive))
      },
    )
    @storage.save_mcpx_config_file(
      paths.servers_config,
      @config.put_server_config(@config.empty_mcpx_config(), server),
    )
    try
      execute_command(
        Retrieve({ target: "srv", operation: List, json_output: true, }),
        home~,
      )
    catch {
      @skill_cli.RetrievalError(message) =>
        assert_true(
          message.contains(if stateful { "stateful" } else { "ephemeral" }),
        )
      error => fail("wrong admission error: \{error}")
    } noraise {
      _ => fail("incompatible target admitted")
    }
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "successful Resource text that resembles an error remains Ok" {
  let home = "/tmp/mcpx-retrieval-result-" + @env.now().to_string()
  let paths = @app_paths.mcpx_app_paths(home)
  defer (@fs.remove_file(paths.servers_config) catch { _ => () })
  let script =
    #|while IFS= read -r line; do
    #|  case "$line" in
    #|    *'"method":"server/discover"'*) printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"],"capabilities":{"resources":{}}}}' ;;
    #|    *'"method":"resources/read"'*) printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"status":"error","resultType":"complete","contents":[{"uri":"u","text":"Error: ordinary text"}],"ttlMs":0,"cacheScope":"public"}}' ;;
    #|    *) exit 1 ;;
    #|  esac
    #|done
  @storage.save_mcpx_config_file(
    paths.servers_config,
    @config.put_server_config(
      @config.empty_mcpx_config(),
      @config.mcp_server_config(
        name="srv",
        transport=Stdio,
        command=Some("/bin/sh"),
        args=["-c", script],
      ),
    ),
  )
  for json_output in [false, true] {
    let result = execute_command(
      Retrieve({ target: "srv", operation: Read("u"), json_output, }),
      home~,
      stdin_json=Some("ignored"),
    )
    guard result is Ok(text) else { fail("ordinary data became an error") }
    assert_true(
      text.has_prefix(
        if json_output {
          "{\"status\":\"error\""
        } else {
          "Error: ordinary text"
        },
      ),
    )
  }
}
