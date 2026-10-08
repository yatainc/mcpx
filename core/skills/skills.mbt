///|
fn require_skills(capabilities : Json) -> Unit raise @protocol.McpProtocolError {
  guard capabilities
    is {
      "resources": Object(_),
      "extensions": { "io.modelcontextprotocol/skills": Object(_), .. },
      ..
    } else {
    raise InvalidResponse("server does not declare the Skills extension")
  }
}

///|
fn require_cacheable(result : Json) -> Unit raise @protocol.McpProtocolError {
  @protocol.require_complete_result(result)
  guard result
    is { "ttlMs": Number(ttl, ..), "cacheScope": "public" | "private", .. } &&
    ttl >= 0 &&
    !ttl.is_inf() &&
    ttl.trunc() == ttl else {
    raise InvalidResponse(
      "result requires nonnegative integer ttlMs and cacheScope",
    )
  }
}

///|
fn require_skill(entry : Json) -> String raise @protocol.McpProtocolError {
  guard entry
    is {
      "uri": String(uri),
      "frontmatter": { "name": String(_), "description": String(_), .. },
      "resources": resources,
      ..
    } else {
    raise InvalidResponse("skill requires uri, frontmatter and resources")
  }
  match resources {
    String("dynamic") => ()
    Array(files) =>
      for file in files {
        guard file
          is {
            "uri": String(_),
            "digest": String(digest),
            "size": Number(size, ..),
            ..
          } &&
          size >= 0 &&
          !size.is_inf() &&
          size.trunc() == size else {
          raise InvalidResponse(
            "skill resource requires uri, digest and integer size",
          )
        }
        if digest.length() != 71 ||
          !digest.has_prefix("sha256:") ||
          !digest[7:].iter().all(c => c is ('0'..='9' | 'a'..='f')) {
          raise InvalidResponse(
            "skill digest must be sha256: followed by 64 lowercase hex digits",
          )
        }
      }
    _ => raise InvalidResponse("skill resources must be an array or dynamic")
  }
  uri
}

///|
/// Retrieve all available pages, without treating the listing as exhaustive.
pub async fn list(
  call : async (String, Map[String, Json]) -> Json,
  capabilities~ : Json,
) -> Array[Json] {
  require_skills(capabilities)
  let fetch_page = async fn(cursor : String?) -> Json {
    let params = Map([])
    if cursor is Some(cursor) {
      params["cursor"] = cursor.to_json()
    }
    let result = call("skills/list", params)
    require_cacheable(result)
    guard result is { "skills": Array(entries), .. } else {
      raise @protocol.InvalidResponse("skills/list requires skills array")
    }
    for entry in entries {
      ignore(require_skill(entry))
    }
    result
  }
  collect_pages(fetch_page(None), cursor => fetch_page(Some(cursor)))
}

///|
/// Get an entry directly. This does not read or load its files.
pub async fn get(
  call : async (String, Map[String, Json]) -> Json,
  capabilities~ : Json,
  uri~ : String,
) -> Json {
  require_skills(capabilities)
  let result = call("skills/get", { "uri": uri.to_json() })
  require_cacheable(result)
  guard result is { "skill": entry, .. } else {
    raise @protocol.InvalidResponse("skills/get requires skill")
  }
  if require_skill(entry) != uri {
    raise @protocol.InvalidResponse("skills/get returned a different URI")
  }
  result
}
