///|
test "bounded frontmatter preserves aliases unknown fields and numeric JSON equality" {
  let text = "﻿---\r\nname: demo\r\ndescription: >-\r\n  hello\r\n  world\r\nmetadata: {yes: yes, quoted: \"true\", enabled: true, hex: 0x10, n: 1.0, unicode: \"\\U0001F600\"}\r\nextra: &a [1, null]\r\ncopy: *a\r\n---\r\nbody"
  let expected : Json = {
    "name": "demo",
    "description": "hello world",
    "metadata": {
      "yes": "yes",
      "quoted": "true",
      "enabled": true,
      "hex": 16,
      "n": 1,
      "unicode": "😀",
    },
    "extra": [1, null],
    "copy": [1, null],
  }
  assert_eq(parse_frontmatter(@utf8.encode(text)), expected)
  assert_eq(
    digest(@utf8.encode("hello")),
    "sha256:2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
  )
}

///|
test "bounded frontmatter refuses cycles malformed UTF8 and missing delimiters" {
  for
    text in [
      "name: demo\n---",
      "---\nname: demo",
      "---\nname: demo\ndescription: Demo\na: &a [*a]\n---",
      "---\nname: demo\ndescription: Demo\nx: .inf\n---",
      "---\nname: demo\ndescription: [\n---",
      "---\nname: demo\ndescription: Demo\nx: " +
      "[".repeat(10000) +
      "0" +
      "]".repeat(10000) +
      "\n---",
      "---\nname: demo\ndescription: Demo\n" +
      [ for i in 0..<1000 => " ".repeat(i) + "x:" ].join("\n") +
      "\n---",
    ] {
    assert_true(
      try {
        ignore(parse_frontmatter(@utf8.encode(text)))
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    try {
      ignore(parse_frontmatter(b"\xff"))
      false
    } catch {
      _ => true
    },
  )
  let doc = @yaml.Yaml::load_from_string("x: [1, 2, 3]")[0]
  assert_true(
    try {
      ignore(yaml_json(doc, { nodes: 1, bytes: 10000, }, 0))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(yaml_json(doc, { nodes: 1000, bytes: 2, }, 0))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "Agent frontmatter constraints count Unicode scalars and preserve future fields" {
  for name in ["demo", "日本語", "école", "١٢٣", "𐐨".repeat(64)] {
    require_frontmatter({
      "name": name.to_json(),
      "description": "😀".repeat(1024).to_json(),
      "future": { "nested": [true, null] },
    })
  }
  for
    name in [
      "",
      "Demo",
      "-demo",
      "demo-",
      "demo--x",
      "demo_",
      "demo\n",
      "💀",
      "𐐨".repeat(65),
    ] {
    assert_true(
      try {
        require_frontmatter({ "name": name.to_json(), "description": "Demo" })
        false
      } catch {
        _ => true
      },
    )
  }
  for
    extra in [
      Json::object({ "description": "" }),
      Json::object({ "description": "😀".repeat(1025).to_json() }),
      Json::object({ "compatibility": "" }),
      Json::object({ "metadata": { "x": 1 } }),
      Json::object({ "allowed-tools": ["all"] }),
    ] {
    let fields : Map[String, Json] = { "name": "demo", "description": "Demo" }
    guard extra is Object(additions) else { fail("fixture") }
    for key, value in additions {
      fields[key] = value
    }
    assert_true(
      try {
        require_frontmatter(fields.to_json())
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "manifest name matching supports Unicode escaped names and nonauthority schemes" {
  let source = Source::new(
    "A",
    capabilities={
      "resources": {},
      "extensions": { "io.modelcontextprotocol/skills": {} },
    },
    call=(_, _) => fail("no I/O"),
  )
  for
    (uri, name) in [
      ("skill://日本語/SKILL.md", "日本語"),
      ("skill://team/%E6%97%A5%E6%9C%AC%E8%AA%9E/SKILL.md", "日本語"),
      ("urn:demo/SKILL.md", "demo"),
    ] {
    let entry : Json = {
      "uri": uri.to_json(),
      "frontmatter": { "name": name.to_json(), "description": "Demo" },
      "resources": [
        {
          "uri": uri.to_json(),
          "digest": ("sha256:" + "0".repeat(64)).to_json(),
          "size": 0,
        },
      ],
    }
    assert_eq(hold_entry(source, entry).uri(), uri)
  }
}

///|
test "manifest supports 512 resources and 16 MiB inclusively" {
  let source = Source::new(
    "A",
    capabilities={
      "resources": {},
      "extensions": { "io.modelcontextprotocol/skills": {} },
    },
    call=(_, _) => fail("no I/O"),
  )
  let uri = "skill://demo/SKILL.md"
  let files : Array[Json] = [
    {
      "uri": uri.to_json(),
      "digest": ("sha256:" + "0".repeat(64)).to_json(),
      "size": 16 * 1024 * 1024,
    },
  ]
  for i in 0..<511 {
    files.push({
      "uri": ("skill://demo/f" + i.to_string()).to_json(),
      "digest": ("sha256:" + "0".repeat(64)).to_json(),
      "size": 0,
    })
  }
  let entry : Json = {
    "uri": uri.to_json(),
    "frontmatter": { "name": "demo", "description": "Demo" },
    "resources": files.to_json(),
  }
  assert_eq(hold_entry(source, entry).files.length(), 512)
  files.push({
    "uri": "skill://demo/excess",
    "digest": ("sha256:" + "0".repeat(64)).to_json(),
    "size": 0,
  })
  assert_true(
    try {
      ignore(
        hold_entry(source, {
          "uri": uri.to_json(),
          "frontmatter": { "name": "demo", "description": "Demo" },
          "resources": files.to_json(),
        }),
      )
      false
    } catch {
      _ => true
    },
  )
  files.pop() |> ignore
  guard files[0] is Object(root) else { fail("fixture") }
  root["size"] = (16 * 1024 * 1024 + 1).to_json()
  assert_true(
    try {
      ignore(hold_entry(source, entry))
      false
    } catch {
      _ => true
    },
  )
}
