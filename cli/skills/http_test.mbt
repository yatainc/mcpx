///|
async test "HTTP CLI retrieval shares native exchange for get, directory and generic contents" {
  let methods = []
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(allow_failure=true, (request, body, conn) => {
        assert_eq(request.headers.get("authorization"), Some("Bearer secret"))
        assert_eq(request.headers.get("mcp-session-id"), None)
        guard @json.parse(body.read_all().text())
          is {
            "id": id,
            "method": String(rpc),
            "params": { "_meta": Object(_), .. },
            ..
          } else {
          fail("missing metadata")
        }
        methods.push(rpc)
        let result : Json = match rpc {
          "server/discover" =>
            {
              "resultType": "complete",
              "supportedVersions": ["2026-07-28"],
              "capabilities": {
                "resources": {},
                "extensions": {
                  "io.modelcontextprotocol/skills": { "directoryRead": true },
                },
              },
            }
          "skills/get" =>
            {
              "resultType": "complete",
              "skill": {
                "uri": "opaque://demo/SKILL.md",
                "frontmatter": { "name": "demo", "description": "Demo" },
                "resources": "dynamic",
              },
              "ttlMs": 0,
              "cacheScope": "public",
              "unknown": true,
            }
          "resources/directory/read" =>
            {
              "resultType": "complete",
              "resources": [{ "uri": "opaque://demo/file", "name": "file" }],
            }
          _ => {
            fail("unexpected method")
            Json::null()
          }
        }
        conn.send_response(200, "OK", extra_headers={
          "content-type": "application/json",
        })
        conn.write(
          Json::object({ "jsonrpc": "2.0", "id": id, "result": result }).stringify(),
        )
        conn.end_response()
      })
    })
    let url = "http://127.0.0.1:\{server.addr.port()}/mcp"
    let headers = { "Authorization": "Bearer secret" }
    let entry = @skills.run_http(
      {
        target: "srv",
        operation: Get("opaque://demo/SKILL.md"),
        json_output: true,
      },
      url~,
      headers~,
    )
    assert_true(@json.parse(entry) is { "unknown": True, .. })
    let directory = @skills.run_http(
      { target: "srv", operation: Read("opaque://demo"), json_output: true, },
      url~,
      headers~,
    )
    assert_true(
      @json.parse(directory)
      is { "pages": [{ "resources": [{ "name": "file", .. }], .. }], .. },
    )
    assert_eq(methods, [
      "server/discover", "skills/get", "server/discover", "resources/directory/read",
    ])
  })
}

///|
async test "HTTP command deadline includes discovery, pagination and directory fallback" {
  for directory in [false, true] {
    let methods = []
    @async.with_timeout(6000, () => {
      @async.with_task_group(group => {
        let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
        defer server.close()
        group.spawn_bg(no_wait=true, () => {
          server.run_forever(allow_failure=true, (_, body, conn) => {
            guard @json.parse(body.read_all().text())
              is { "id": id, "method": String(rpc), .. } else {
              fail("invalid request")
            }
            methods.push(rpc)
            @async.sleep(600)
            let reply : Json = if rpc == "resources/directory/read" {
              {
                "jsonrpc": "2.0",
                "id": id,
                "error": { "code": -32602, "message": "file" },
              }
            } else {
              let result : Json = match rpc {
                "server/discover" =>
                  {
                    "resultType": "complete",
                    "supportedVersions": ["2026-07-28"],
                    "capabilities": {
                      "resources": {},
                      "extensions": {
                        "io.modelcontextprotocol/skills": {
                          "directoryRead": true,
                        },
                      },
                    },
                  }
                "skills/list" =>
                  if methods.length() == 2 {
                    {
                      "resultType": "complete",
                      "skills": [],
                      "nextCursor": "next",
                      "ttlMs": 0,
                      "cacheScope": "public",
                    }
                  } else {
                    {
                      "resultType": "complete",
                      "skills": [],
                      "ttlMs": 0,
                      "cacheScope": "public",
                    }
                  }
                "resources/read" =>
                  {
                    "resultType": "complete",
                    "contents": [],
                    "ttlMs": 0,
                    "cacheScope": "public",
                  }
                _ => {
                  fail("unexpected method")
                  Json::null()
                }
              }
              { "jsonrpc": "2.0", "id": id, "result": result }
            }
            conn.send_response(200, "OK", extra_headers={
              "content-type": "application/json",
            })
            conn.write(reply.stringify())
            conn.end_response()
          })
        })
        try
          @skills.run_http(
            {
              target: "srv",
              operation: if directory {
                Read("u")
              } else {
                List
              },
              json_output: true,
            },
            url="http://127.0.0.1:\{server.addr.port()}/mcp",
            headers=Map([]),
            timeout_ms=1600,
          )
        catch {
          @async.TimeoutError => ()
          error => fail("wrong timeout: \{error}")
        } noraise {
          _ => fail("deadline reset between requests")
        }
        assert_eq(
          methods,
          if directory {
            ["server/discover", "resources/directory/read", "resources/read"]
          } else {
            ["server/discover", "skills/list", "skills/list"]
          },
        )
      })
    })
  }
}
