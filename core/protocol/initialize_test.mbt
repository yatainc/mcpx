///|
test "initialize: rejects malformed results without client state" {
  for
    result in [
      Json::null(),
      Json::empty_object(),
      Json::object({ "protocolVersion": 42 }),
    ] {
    try decode_mcp_initialize_result(result) catch {
      InvalidResponse(_) => ()
      _ => fail("expected invalid initialize result")
    } noraise {
      _ => fail("expected error")
    }
  }
}

///|
test "initialize: retains capabilities and optional server info" {
  let empty = decode_mcp_initialize_result({ "protocolVersion": "2025-03-26" })
  json_inspect(empty.capabilities, content={})
  @debug.debug_inspect(empty.server_name, content="None")
  @debug.debug_inspect(empty.server_version, content="None")
  let info = decode_mcp_initialize_result({
    "protocolVersion": "2025-11-25",
    "capabilities": { "extension": { "flag": true } },
    "serverInfo": { "name": "srv", "version": "1" },
  })
  json_inspect(info.capabilities, content={ "extension": { "flag": true } })
  @debug.debug_inspect(info.server_name, content="Some(\"srv\")")
  @debug.debug_inspect(info.server_version, content="Some(\"1\")")
}
