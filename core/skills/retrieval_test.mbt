///|
fn capabilities(directory? : Bool = false) -> Json {
  {
    "resources": {},
    "extensions": {
      "io.modelcontextprotocol/skills": { "directoryRead": directory.to_json() },
    },
  }
}

///|
fn entry(uri? : String = "other://team/demo/SKILL.md") -> Json {
  {
    "uri": uri.to_json(),
    "frontmatter": { "name": "demo", "description": "Demo", "extra": [1, true] },
    "resources": "dynamic",
    "extra": {},
  }
}

///|
async test "Skills list preserves pages and opaque empty cursors; get is direct" {
  let requests : Array[(String, Json)] = []
  let first : Json = {
    "resultType": "complete",
    "skills": [entry()],
    "nextCursor": "",
    "ttlMs": 0,
    "cacheScope": "private",
    "extra": "first",
  }
  let last : Json = {
    "resultType": "complete",
    "skills": [entry(uri="other://different/demo/SKILL.md")],
    "ttlMs": 20,
    "cacheScope": "private",
    "extra": "last",
  }
  let pages = @skills.list(
    (rpc, params) => {
      requests.push((rpc, params.to_json()))
      if params.get("cursor") is None {
        first
      } else {
        last
      }
    },
    capabilities=capabilities(),
  )
  assert_eq(pages, [first, last])
  assert_eq(requests, [("skills/list", {}), ("skills/list", { "cursor": "" })])
  requests.clear()
  for
    resources in [
      Json::string("dynamic"),
      Json::array([
        {
          "uri": "other://team/demo/SKILL.md",
          "digest": Json::string("sha256:" + "a".repeat(64)),
          "size": 2,
        },
      ]),
    ] {
    let skill : Json = {
      "uri": "other://team/demo/SKILL.md",
      "frontmatter": { "name": "demo", "description": "Demo", "unknown": {} },
      "resources": resources,
    }
    let reply : Json = {
      "resultType": "complete",
      "skill": skill,
      "ttlMs": 0,
      "cacheScope": "public",
    }
    let got = @skills.get(
      (rpc, params) => {
        requests.push((rpc, params.to_json()))
        reply
      },
      capabilities=capabilities(),
      uri="other://team/demo/SKILL.md",
    )
    assert_eq(got, reply)
  }
  assert_eq(requests.length(), 2)
  assert_true(requests.iter().all(pair => pair.0 == "skills/get"))
}

///|
async test "Skills require their capability and required result shape" {
  for
    caps in [
      Json::null(),
      Json::empty_object(),
      Json::object({
        "resources": {},
        "extensions": { "io.modelcontextprotocol/skills": true },
      }),
    ] {
    try
      @skills.list(
        (_, _) => {
          fail("must not call")
          Json::null()
        },
        capabilities=caps,
      )
    catch {
      @protocol.InvalidResponse(_) => ()
      _ => fail("wrong capability error")
    } noraise {
      _ => fail("missing capability accepted")
    }
  }
  for
    result in [
      Json::object({ "skills": [] }),
      Json::object({
        "resultType": "input_required",
        "skills": [],
        "ttlMs": 0,
        "cacheScope": "public",
      }),
      Json::object({
        "resultType": "complete",
        "skills": [],
        "cacheScope": "public",
      }),
      Json::object({
        "resultType": "complete",
        "skills": [],
        "ttlMs": 1.5,
        "cacheScope": "public",
      }),
      Json::object({
        "resultType": "complete",
        "skills": [],
        "ttlMs": 0,
        "cacheScope": "other",
      }),
      Json::object({
        "resultType": "complete",
        "skills": [{ "uri": "u" }],
        "ttlMs": 0,
        "cacheScope": "public",
      }),
      Json::object({
        "resultType": "complete",
        "skills": [],
        "nextCursor": 1,
        "ttlMs": 0,
        "cacheScope": "public",
      }),
    ] {
    try @skills.list((_, _) => result, capabilities=capabilities()) catch {
      @protocol.InvalidResponse(_) => ()
      _ => fail("wrong schema error")
    } noraise {
      _ => fail("invalid result accepted")
    }
  }
  try
    @skills.get(
      (_, _) => {
        "resultType": "complete",
        "skill": entry(),
        "ttlMs": 0,
        "cacheScope": "public",
      },
      capabilities=capabilities(),
      uri="different",
    )
  catch {
    @protocol.InvalidResponse(_) => ()
    _ => fail("wrong URI error")
  } noraise {
    _ => fail("different URI accepted")
  }
}

///|
async test "generic resources preserve text, blob, multiple contents and unknown fields" {
  let result : Json = {
    "resultType": "complete",
    "contents": [
      { "uri": "custom://text", "text": "Error: ordinary text", "extra": 1 },
      {
        "uri": "custom://binary",
        "blob": "AAE=",
        "mimeType": "application/octet-stream",
      },
    ],
    "ttlMs": 0,
    "cacheScope": "private",
    "status": "error",
  }
  let requests = []
  let read = @skills.read(
    (rpc, params) => {
      requests.push((rpc, params.to_json()))
      result
    },
    capabilities={},
    uri="custom://opaque?x=1",
  )
  guard read is Content(content) else { fail("expected content") }
  assert_eq(content, result)
  assert_eq(requests, [("resources/read", { "uri": "custom://opaque?x=1" })])
  for
    contents in [
      Json::array([{ "uri": "u" }]),
      Json::array([{ "uri": "u", "text": "x", "blob": "AA==" }]),
    ] {
    try
      @skills.read(
        (_, _) => {
          "resultType": "complete",
          "contents": contents,
          "ttlMs": 0,
          "cacheScope": "public",
        },
        capabilities={},
        uri="u",
      )
    catch {
      @protocol.InvalidResponse(_) => ()
      _ => fail("wrong content error")
    } noraise {
      _ => fail("invalid content accepted")
    }
  }
}

///|
async test "directory pagination and empty directory need no caching hints" {
  for empty in [false, true] {
    let calls = []
    let first : Json = if empty {
      { "resultType": "complete", "resources": [] }
    } else {
      {
        "resultType": "complete",
        "resources": [
          { "uri": "d/sub", "name": "sub", "mimeType": "inode/directory" },
        ],
        "nextCursor": "",
      }
    }
    let last : Json = {
      "resultType": "complete",
      "resources": [{ "uri": "d/file", "name": "file", "unknown": true }],
    }
    let result = @skills.read(
      (rpc, params) => {
        calls.push((rpc, params.to_json()))
        if params.get("cursor") is None {
          first
        } else {
          last
        }
      },
      capabilities=capabilities(directory=true),
      uri="d",
    )
    guard result is Directory(pages) else { fail("expected directory") }
    assert_eq(pages, if empty { [first] } else { [first, last] })
    assert_eq(calls.length(), if empty { 1 } else { 2 })
    assert_true(calls.iter().all(pair => pair.0 == "resources/directory/read"))
  }
}

///|
async test "only the first directory RPC invalid-params selects content fallback" {
  let calls = []
  let result = @skills.read(
    (rpc, _) => {
      calls.push(rpc)
      if rpc == "resources/directory/read" {
        raise @protocol.RemoteError(-32602, "file")
      }
      {
        "resultType": "complete",
        "contents": [],
        "ttlMs": 0,
        "cacheScope": "public",
      }
    },
    capabilities=capabilities(directory=true),
    uri="u",
  )
  assert_true(result is Content(_))
  assert_eq(calls, ["resources/directory/read", "resources/read"])
  for scenario in 0..<3 {
    calls.clear()
    try
      @skills.read(
        (rpc, _) => {
          calls.push(rpc)
          if scenario == 0 {
            raise @protocol.RemoteError(-32603, "broken")
          }
          if scenario == 1 {
            return { "resultType": "complete", "resources": "invalid" }
          }
          if calls.length() == 1 {
            return {
              "resultType": "complete",
              "resources": [],
              "nextCursor": "next",
            }
          }
          raise @protocol.RemoteError(-32602, "invalid cursor")
        },
        capabilities=capabilities(directory=true),
        uri="u",
      )
    catch {
      @protocol.RemoteError(_, _) | @protocol.InvalidResponse(_) => ()
      _ => fail("wrong fallback error")
    } noraise {
      _ => fail("invalid directory read succeeded")
    }
    assert_false(calls.contains("resources/read"))
  }
}
