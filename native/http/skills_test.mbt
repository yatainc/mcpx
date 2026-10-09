///|
async test "native HTTP source binds origin and cumulatively bounds streamed responses" {
  let uri = "skill://demo/SKILL.md"
  let text = "---\nname: demo\ndescription: Demo\n---\n" + "x".repeat(2048)
  let bytes = @utf8.encode(text)
  @async.with_task_group(group => {
    let server = @async_http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let received = Ref(0)
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(allow_failure=true, (_, body, conn) => {
        guard @json.parse(body.read_all().text())
          is { "id": id, "method": String(rpc), .. } else {
          fail("request")
        }
        let result : Json = match rpc {
          "server/discover" =>
            {
              "resultType": "complete",
              "supportedVersions": ["2026-07-28"],
              "capabilities": {
                "resources": {},
                "extensions": { "io.modelcontextprotocol/skills": {} },
              },
              "serverInfo": { "name": "impostor" },
            }
          "skills/get" =>
            {
              "resultType": "complete",
              "ttlMs": 0,
              "cacheScope": "private",
              "skill": {
                "uri": uri.to_json(),
                "frontmatter": { "name": "demo", "description": "Demo" },
                "resources": [
                  {
                    "uri": uri.to_json(),
                    "digest": ("sha256:" +
                    @hex.encode(Bytes::from_array(@crypto.sha256(bytes)[:]))).to_json(),
                    "size": bytes.length().to_json(),
                  },
                ],
              },
            }
          _ =>
            {
              "resultType": "complete",
              "ttlMs": 0,
              "cacheScope": "private",
              "contents": [{ "uri": uri.to_json(), "text": text.to_json() }],
            }
        }
        conn.send_response(200, "OK", extra_headers={
          "content-type": "application/json",
        })
        let wire = Json::object({ "jsonrpc": "2.0", "id": id, "result": result }).stringify()
        let size = @utf8.encode(wire).length()
        assert_true(size < 2500, msg="each response must fit independently")
        received.val += size
        conn.write(wire)
        conn.end_response()
      })
    })
    let url = "http://" + server.addr.to_string()
    let source = @http.http_mcp_skill_source(url~, headers=Map([]), origin="A")
    let held = source.hold(uri)
    assert_eq(held.read(uri).bytes, bytes)
    assert_eq(held.origin(), "A")
    received.val = 0
    let source = @http.http_mcp_skill_source(
      url~,
      headers=Map([]),
      origin="B",
      budget=@receive.Budget::new(limit=2500),
    )
    let held = source.hold(uri)
    assert_true(
      try {
        ignore(held.read(uri))
        false
      } catch {
        @core_http.Network(message) => message.contains("receive limit")
        error => raise error
      },
    )
    assert_true(
      received.val > 2500,
      msg="only the cumulative limit is exceeded",
    )
  })
}
