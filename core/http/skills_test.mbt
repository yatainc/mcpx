///|
async test "HTTP retrieval discovers once, carries metadata and decodes SSE notifications" {
  let requests : Array[Json] = []
  let fetch : async (@http.HttpRequest) -> @http.HttpResponse = request => {
    let message = @json.parse(request.body)
    requests.push(message)
    assert_eq(request.headers.get("Authorization"), Some("Bearer secret"))
    assert_false(
      request.headers
      .keys()
      .any(key => key.equal_ignore_ascii_case("Mcp-Session-Id")),
    )
    guard message
      is {
        "id": id,
        "method": String(rpc),
        "params": { "_meta": Object(_), .. },
        ..
      } else {
      fail("missing metadata")
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
        }
      "skills/list" =>
        if requests.length() == 2 {
          {
            "resultType": "complete",
            "skills": [],
            "nextCursor": "",
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
      _ => {
        fail("unexpected method")
        Json::null()
      }
    }
    let reply : Json = { "jsonrpc": "2.0", "id": id, "result": result }
    if rpc == "server/discover" {
      @http.http_response(status_code=200, body=reply.stringify())
    } else {
      @http.http_response(
        status_code=200,
        content_type=Some("text/event-stream"),
        body="data: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\"}\n\n" +
          "data: " +
          reply.stringify() +
          "\n\n",
      )
    }
  }
  let pages = @http.list_skills(
    fetch,
    @http.http_endpoint(url="https://example.test/mcp", headers={
      "Authorization": "Bearer secret",
      "Mcp-Session-Id": "old",
    }),
  )
  assert_eq(pages.length(), 2)
  assert_eq(requests.length(), 3)
  assert_true(
    requests[0] is { "id": Number(1, ..), "method": "server/discover", .. },
  )
  assert_true(
    requests[1] is { "id": Number(2, ..), "method": "skills/list", .. },
  )
  assert_true(
    requests[2] is { "id": Number(3, ..), "params": { "cursor": "", .. }, .. },
  )
}

///|
async test "HTTP directory fallback respects status, envelope and first-page boundary" {
  for status in [200, 400, 404, 401, 403, 429, 500, 503] {
    for valid_id in [true, false] {
      let methods = []
      let fetch : async (@http.HttpRequest) -> @http.HttpResponse = request => {
        guard @json.parse(request.body)
          is { "id": id, "method": String(rpc), .. } else {
          fail("invalid request")
        }
        methods.push(rpc)
        let result : Json = if rpc == "server/discover" {
          {
            "resultType": "complete",
            "supportedVersions": ["2026-07-28"],
            "capabilities": {
              "extensions": {
                "io.modelcontextprotocol/skills": { "directoryRead": true },
              },
            },
          }
        } else {
          {
            "resultType": "complete",
            "contents": [],
            "ttlMs": 0,
            "cacheScope": "public",
          }
        }
        if rpc == "resources/directory/read" {
          let reply : Json = {
            "jsonrpc": "2.0",
            "id": if valid_id {
              id
            } else {
              Json::number(99)
            },
            "error": { "code": -32602, "message": "file" },
          }
          @http.http_response(status_code=status, body=reply.stringify())
        } else {
          @http.http_response(
            status_code=200,
            body=Json::object({ "jsonrpc": "2.0", "id": id, "result": result }).stringify(),
          )
        }
      }
      let fallback = valid_id &&
        (status == 200 || status == 400 || status == 404)
      try
        @http.read_resource(
          fetch,
          @http.http_endpoint(url="https://example.test/mcp"),
          uri="opaque",
        )
      catch {
        HttpStatus(code) => {
          assert_false(fallback)
          assert_eq(code, status)
        }
        Protocol(_) => {
          assert_false(valid_id)
          assert_false(fallback)
        }
        _ => fail("unexpected fallback error")
      } noraise {
        result => {
          assert_true(fallback)
          assert_true(result is Content(_))
        }
      }
      assert_eq(methods.contains("resources/read"), fallback)
    }
  }
}

///|
async test "retrieval rejects initialize mode before making requests" {
  try
    @http.list_skills(
      _ => {
        fail("must not connect")
        @http.http_response(status_code=200, body="")
      },
      @http.http_endpoint(url="https://example.test", mode=Stateful),
    )
  catch {
    ModeProtocolIncompatible(_, _) => ()
    _ => fail("wrong lifecycle error")
  } noraise {
    _ => fail("initialize accepted")
  }
}
