///|
fn peer_script() -> String {
  (
    #|import sys,json,hashlib,base64
    #|uri='skill://demo/SKILL.md'
    #|body=b'---\nname: demo\ndescription: Demo\n---\n'+sys.argv[1].encode()
    #|for line in sys.stdin:
    #| q=json.loads(line); method=q['method']
    #| if method=='server/discover':
    #|  r={'resultType':'complete','supportedVersions':['2026-07-28'],'capabilities':{'resources':{},'extensions':{'io.modelcontextprotocol/skills':{}}},'serverInfo':{'name':'impostor'}}
    #| elif method=='skills/get':
    #|  r={'resultType':'complete','ttlMs':0,'cacheScope':'private','skill':{'uri':uri,'frontmatter':{'name':'demo','description':'Demo'},'resources':[{'uri':uri,'digest':'sha256:'+hashlib.sha256(body).hexdigest(),'size':len(body)}]}}
    #| else:
    #|  assert method=='resources/read' and q['params']['uri']==uri
    #|  r={'resultType':'complete','ttlMs':0,'cacheScope':'private','contents':[{'uri':uri,'blob':base64.b64encode(body).decode()}],'unknown':True}
    #| print(json.dumps({'jsonrpc':'2.0','id':q['id'],'result':r}),flush=True)
  )
}

///|
async test "native fixed source verifies peer content and survives request serialization" {
  let script = peer_script()
  @async.with_task_group(group => {
    for origin in ["A", "B"] {
      let client = @stdio.stdio_mcp_connect(
        group,
        command="python3",
        args=["-c", script, origin],
        env=Map([]),
        cwd=None,
        mode=Stateless,
        receive_budget=@receive.Budget::new(),
      )
      defer client.close()
      let source = client.skill_source(origin)
      let held = source.hold("skill://demo/SKILL.md")
      let content = held.read(held.uri())
      assert_eq(content.origin, origin)
      assert_true(@utf8.decode(content.bytes).has_suffix(origin))
      assert_true(content.result is { "unknown": True, .. })
      let entries = @async.all([
        () => source.hold(held.uri()),
        () => source.hold(held.uri()),
        () => source.hold(held.uri()),
      ])
      for entry in entries {
        assert_true(held.same_content(entry))
      }
    }
  })
}

///|
async test "oversized resource poisons a bounded source before another request" {
  @async.with_task_group(group => {
    let client = @stdio.stdio_mcp_connect(
      group,
      command="python3",
      args=["-c", peer_script(), "x".repeat(8192)],
      env=Map([]),
      cwd=None,
      mode=Stateless,
      receive_budget=@receive.Budget::new(limit=4096),
    )
    defer client.close()
    let held = client.skill_source("A").hold("skill://demo/SKILL.md")
    assert_true(
      try {
        ignore(held.read(held.uri()))
        false
      } catch {
        @stdio.ReadFailed(message) => message.contains("receive limit")
        error => raise error
      },
    )
    assert_true(
      try {
        ignore(client.get_skill(uri=held.uri()))
        false
      } catch {
        Protocol(message) =>
          message ==
          "stdio connection is unusable after bounded receive failure"
        error => raise error
      },
    )
    client.close()
    assert_true(
      try {
        ignore(held.read(held.uri()))
        false
      } catch {
        @stdio.Protocol(_) => true
        error => raise error
      },
    )
  })
}

///|
async test "bounded connection refuses legacy or fallback modes before spawn" {
  @async.with_task_group(group => {
    for mode in [@config.McpConnectionMode::Stateful, Auto] {
      try {
        let client = @stdio.stdio_mcp_connect(
          group,
          command="/must/not/spawn",
          args=[],
          env=Map([]),
          cwd=None,
          mode~,
          receive_budget=@receive.Budget::new(),
        )
        client.close()
      } catch {
        @stdio.Protocol(message) =>
          assert_eq(message, "bounded retrieval requires stateless MCP")
        error => raise error
      } noraise {
        _ => fail("bounded connection must not admit a legacy mode")
      }
    }
  })
}

///|
async test "native discovery rejects no-newline output before outer timeout" {
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      let failed = try {
        let client = @stdio.stdio_mcp_connect(
          group,
          command="python3",
          args=[
            "-c", "import sys;sys.stdout.write('x'*8192);sys.stdout.flush();sys.stdin.read()",
          ],
          env=Map([]),
          cwd=None,
          mode=Stateless,
          receive_budget=@receive.Budget::new(limit=4096),
        )
        defer client.close()
        false
      } catch {
        @stdio.Protocol(message) => {
          assert_true(message.contains("receive limit"), msg=message)
          true
        }
        error => raise error
      }
      assert_true(failed)
    })
  })
}
