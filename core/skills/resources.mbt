///|
pub(all) enum ReadResult {
  Content(Json)
  Directory(Array[Json])
}

///|
fn directory_enabled(
  capabilities : Json,
) -> Bool raise @protocol.McpProtocolError {
  match capabilities {
    {
      "extensions": {
        "io.modelcontextprotocol/skills": { "directoryRead": value, .. },
        ..
      },
      ..
    } =>
      match value {
        True => true
        False => false
        _ => raise InvalidResponse("directoryRead must be boolean")
      }
    _ => false
  }
}

///|
async fn read_content(
  call : async (String, Map[String, Json]) -> Json,
  uri : String,
) -> Json {
  let result = call("resources/read", { "uri": uri.to_json() })
  require_cacheable(result)
  guard result is { "contents": Array(contents), .. } else {
    raise @protocol.InvalidResponse("resources/read requires contents array")
  }
  for content in contents {
    guard content is { "uri": String(_), .. } else {
      raise @protocol.InvalidResponse("resource content requires uri")
    }
    match content {
      { "text": String(_), "blob"? : None, .. }
      | { "blob": String(_), "text"? : None, .. } => ()
      _ =>
        raise @protocol.InvalidResponse(
          "resource content requires text or blob",
        )
    }
  }
  result
}

///|
fn require_directory(result : Json) -> Unit raise @protocol.McpProtocolError {
  @protocol.require_complete_result(result)
  guard result is { "resources": Array(children), .. } else {
    raise InvalidResponse("directory result requires resources array")
  }
  for child in children {
    guard child is { "uri": String(_), "name": String(_), .. } else {
      raise InvalidResponse("directory child requires uri and name")
    }
  }
}

///|
/// Read ordinary contents or all direct directory pages. No Skill is loaded.
pub async fn read(
  call : async (String, Map[String, Json]) -> Json,
  capabilities~ : Json,
  uri~ : String,
) -> ReadResult {
  if !directory_enabled(capabilities) {
    return Content(read_content(call, uri))
  }
  let first = call("resources/directory/read", { "uri": uri.to_json() }) catch {
    @protocol.RemoteError(-32602, _) => return Content(read_content(call, uri))
    error => raise error
  }
  require_directory(first)
  Directory(
    collect_pages(
      first,
      cursor => {
        let page = call("resources/directory/read", {
          "uri": uri.to_json(),
          "cursor": cursor.to_json(),
        })
        require_directory(page)
        page
      },
      items_key="resources",
    ),
  )
}
