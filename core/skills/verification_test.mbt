///|
fn verified_file(uri : String, body : String) -> Json {
  let bytes = @utf8.encode(body)
  {
    "uri": uri.to_json(),
    "digest": ("sha256:" +
    @hex.encode(Bytes::from_array(@crypto.sha256(bytes)[:]))).to_json(),
    "size": bytes.length().to_json(),
  }
}

///|
fn verified_entry(uri : String, body : String) -> Json {
  {
    "uri": uri.to_json(),
    "frontmatter": { "name": "demo", "description": "Demo", "extra": [1, true] },
    "resources": [verified_file(uri, body)],
    "unknown": 42,
  }
}

///|
fn verified_result(field : String, value : Json) -> Json {
  let fields : Map[String, Json] = {
    "resultType": "complete",
    "ttlMs": 0,
    "cacheScope": "private",
    "unknown": true,
  }
  fields[field] = value
  fields.to_json()
}

///|
async test "held source owns entry, rejects unlisted before IO and compares origin" {
  let uri = "other://team/demo/SKILL.md"
  let body = "---\nname: demo\ndescription: Demo\nextra: [1, true]\n---\nbody"
  let entry = verified_entry(uri, body)
  let gets = Ref(0)
  let reads = Ref(0)
  let caps = capabilities()
  let source = @skills.Source::new("A", capabilities=caps, call=(rpc, params) => {
    if rpc == "resources/read" {
      reads.val += 1
    }
    assert_eq(params.get("uri"), Some(uri.to_json()))
    match rpc {
      "skills/get" => {
        gets.val += 1
        verified_result("skill", entry)
      }
      "resources/read" =>
        verified_result("contents", [
          { "uri": uri.to_json(), "text": body.to_json() },
        ])
      _ => fail("unexpected RPC")
    }
  })
  guard caps is Object(fields) else { fail("fixture") }
  fields["extensions"] = {}
  let held = source.hold(uri)
  assert_eq(gets.val, 1)
  assert_eq(reads.val, 0)
  guard entry is Object(fields) else { fail("fixture") }
  fields["frontmatter"] = { "name": "other", "description": "mutated" }
  let copy = held.entry()
  guard copy is Object(fields) else { fail("fixture") }
  fields["resources"] = []
  guard held.entry() is { "resources": Array(retained), .. } else {
    fail("fixture")
  }
  assert_eq(retained.length(), 1)
  assert_true(
    try {
      ignore(held.read("other://team/demo/missing.md"))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(reads.val, 0)
  let content = held.read(uri)
  assert_eq(content.origin, "A")
  assert_eq(content.skill_uri, uri)
  assert_eq(content.uri, uri)
  assert_eq(content.bytes, @utf8.encode(body))
  assert_eq(gets.val, 1)
  assert_eq(reads.val, 1)
  let other = @skills.Source::new("B", capabilities=capabilities(), call=(_, _) => {
    verified_result("skill", verified_entry(uri, body))
  }).hold(uri)
  assert_false(held.same_content(other))
}

///|
async test "held content mismatch does not refresh; root URI and multipart are checked" {
  let uri = "skill://demo/SKILL.md"
  let body = "---\nname: demo\ndescription: Demo\nextra: [1, true]\n---\nbody"
  let contents = Ref(
    Json::array([{ "uri": uri.to_json(), "text": body.to_json() }]),
  )
  let gets = Ref(0)
  let source = @skills.Source::new("A", capabilities=capabilities(), call=(
    rpc,
    _,
  ) => {
    if rpc == "skills/get" {
      gets.val += 1
      verified_result("skill", verified_entry(uri, body))
    } else {
      verified_result("contents", contents.val)
    }
  })
  let held = source.hold(uri)
  for
    invalid in [
      Json::array([{ "uri": uri.to_json(), "text": (body + "x").to_json() }]),
      Json::array([
        {
          "uri": uri.to_json(),
          "text": (body[:body.length() - 4] + "evil").to_json(),
        },
      ]),
      Json::array([{ "uri": "skill://other/SKILL.md", "text": body.to_json() }]),
      Json::array([
        { "uri": uri.to_json(), "text": body.to_json() },
        { "uri": uri.to_json(), "text": body.to_json() },
      ]),
      Json::array([{ "uri": uri.to_json(), "blob": "not base64!" }]),
    ] {
    contents.val = invalid
    let rejected = try {
      ignore(held.read(uri))
      false
    } catch {
      @skills.VerificationError(..) => true
      error => raise error
    }
    assert_true(rejected)
    assert_eq(gets.val, 1)
  }
  contents.val = [
    {
      "uri": uri.to_json(),
      "blob": @base64.encode(@utf8.encode(body)).to_json(),
    },
  ]
  assert_eq(held.read(uri).bytes, @utf8.encode(body))
}

///|
async test "text rejects before full encoding and Unicode uses raw byte lengths" {
  let uri = "skill://demo/SKILL.md"
  let nested = "skill://demo/data.txt"
  let body = "---\nname: demo\ndescription: Demo\nextra: [1, true]\n---\nbody"
  let entry = verified_entry(uri, body)
  guard entry is Object(fields) else { fail("fixture") }
  fields["resources"] = [
    verified_file(uri, body),
    verified_file(nested, "😀"),
  ]
  let text = Ref("😀")
  let held = @skills.Source::new("A", capabilities=capabilities(), call=(rpc, _) => {
    if rpc == "skills/get" {
      verified_result("skill", entry)
    } else {
      verified_result("contents", [
        { "uri": nested.to_json(), "text": text.val.to_json() },
      ])
    }
  }).hold(uri)
  assert_eq(held.read(nested).bytes, @utf8.encode("😀"))
  for
    (value, reason) in [
      ("x".repeat(10000), "text exceeds the declared byte length"),
      ("😀😀", "byte length differs from the held entry"),
    ] {
    text.val = value
    try ignore(held.read(nested)) catch {
      @skills.VerificationError(
        origin~,
        skill_uri~,
        uri=returned,
        reason=actual
      ) => {
        assert_eq(origin, "A")
        assert_eq(skill_uri, uri)
        assert_eq(returned, nested)
        assert_eq(actual, reason)
      }
      error => raise error
    } noraise {
      _ => fail("expected byte length refusal")
    }
  }
}

///|
async test "root YAML must match every frontmatter field; nested root is ordinary bytes" {
  let uri = "skill://demo/SKILL.md"
  let nested = "skill://demo/nested/SKILL.md"
  let body = "---\nname: demo\ndescription: Demo\nextra: [1, false]\n---\nbody"
  let entry = verified_entry(uri, body)
  guard entry is Object(fields) else { fail("fixture") }
  fields["resources"] = [
    verified_file(uri, body),
    verified_file(nested, "not YAML"),
  ]
  let source = @skills.Source::new("A", capabilities=capabilities(), call=(
    rpc,
    params,
  ) => {
    if rpc == "skills/get" {
      verified_result("skill", entry)
    } else {
      let requested = params["uri"]
      verified_result("contents", [
        {
          "uri": requested,
          "text": if requested == uri.to_json() {
            body.to_json()
          } else {
            "not YAML"
          },
        },
      ])
    }
  })
  let held = source.hold(uri)
  assert_true(
    try {
      ignore(held.read(uri))
      false
    } catch {
      @skills.VerificationError(..) => true
      error => raise error
    },
  )
  assert_eq(held.read(nested).bytes, @utf8.encode("not YAML"))
}

///|
async test "held manifest rejects duplicates omission traversal and dynamic entries" {
  let uri = "github://owner/repo/demo/SKILL.md?ref=main"
  let body = "root"
  for
    resources in [
      Json::array([]),
      Json::array([verified_file(uri, body), verified_file(uri, body)]),
      Json::array([
        verified_file(uri, body),
        verified_file("github://owner/repo/demo/../outside", ""),
      ]),
      Json::array([
        verified_file(uri, body),
        verified_file("github://owner/repo/demo/%2e%2e/outside", ""),
      ]),
      Json::array([
        verified_file(uri, body),
        verified_file("github://owner/repo/demo2/outside", ""),
      ]),
      Json::array([
        verified_file(uri, body),
        verified_file("github://other/repo/demo/f", ""),
      ]),
      Json::string("dynamic"),
    ] {
    let entry = verified_entry(uri, body)
    guard entry is Object(fields) else { fail("fixture") }
    fields["resources"] = resources
    let source = @skills.Source::new("A", capabilities=capabilities(), call=(
      _,
      _,
    ) => verified_result("skill", entry))
    assert_true(
      try {
        ignore(source.hold(uri))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
async test "verified read supports a 16 MiB root in a 512-file Skill without prefetch" {
  let uri = "skill://demo/SKILL.md"
  let header = "---\nname: demo\ndescription: Demo\nextra: [1, true]\n---\n"
  let body = header + "x".repeat(16 * 1024 * 1024 - header.length())
  let entry = verified_entry(uri, body)
  guard entry is Object(fields) else { fail("fixture") }
  guard fields["resources"] is Array(files) else { fail("fixture") }
  for i in 0..<511 {
    files.push(verified_file("skill://demo/f" + i.to_string(), ""))
  }
  let calls = Ref(0)
  let source = @skills.Source::new("A", capabilities=capabilities(), call=(
    rpc,
    params,
  ) => {
    calls.val += 1
    assert_eq(params.get("uri"), Some(uri.to_json()))
    if rpc == "skills/get" {
      verified_result("skill", entry)
    } else {
      verified_result("contents", [
        {
          "uri": uri.to_json(),
          "blob": @base64.encode(@utf8.encode(body)).to_json(),
        },
      ])
    }
  })
  let held = source.hold(uri)
  assert_eq(calls.val, 1)
  assert_eq(held.read(uri).bytes.length(), 16 * 1024 * 1024)
  assert_eq(calls.val, 2)
}

///|
async test "held content comparison ignores ordering metadata and declared sizes" {
  let uri = "skill://demo/SKILL.md"
  let entry = verified_entry(uri, "root")
  guard entry is Object(fields) &&
    fields["resources"] is Array(files) &&
    files[0] is Object(file) else {
    fail("fixture")
  }
  files.push(verified_file("skill://demo/support", ""))
  let source = @skills.Source::new("A", capabilities=capabilities(), call=(_, _) => {
    verified_result("skill", entry)
  })
  let held = source.hold(uri)
  fields["unknown"] = false
  file["size"] = 0
  fields["resources"] = [files[1], files[0]]
  assert_true(held.same_content(source.hold(uri)))
  file["digest"] = ("sha256:" + "0".repeat(64)).to_json()
  assert_false(held.same_content(source.hold(uri)))
}
