///|
async test "tool pagination: preserves tool order and advances cursors" {
  let first : Json = {
    "resultType": "complete",
    "tools": [{ "name": "first", "inputSchema": {} }],
    "nextCursor": "next",
    "cacheScope": "public",
  }
  let second : Json = {
    "resultType": "complete",
    "tools": [
      {
        "name": "second",
        "inputSchema": {
          "properties": {
            "value": { "type": "array", "x-mcp-header": "UnsupportedByHTTP" },
          },
        },
      },
    ],
    "cacheScope": "private",
  }
  let cursors = []
  let tools = @tools.list(cursor => {
    cursors.push(cursor)
    match cursor {
      None => first
      Some("next") => second
      _ => fail("unexpected cursor")
    }
  })
  @debug.debug_inspect(cursors, content="[None, Some(\"next\")]")
  inspect(tools.map(tool => tool.name).join(","), content="first,second")
  ignore(tools.pop())
  json_inspect(first, content={
    "resultType": "complete",
    "tools": [{ "name": "first", "inputSchema": {} }],
    "nextCursor": "next",
    "cacheScope": "public",
  })
  inspect(@tools.decode_list_result(second).tools[0].name, content="second")
}
