///|
fn origin(target : String) -> String {
  if target.has_prefix("https://") || target.has_prefix("http://") {
    "url:sha256:" +
    @hex.encode(Bytes::from_array(@crypto.sha256(@utf8.encode(target))[:]))
  } else {
    "config:" + target
  }
}

///|
fn render_skill_result(origin : String, result : Json) -> String {
  Json::object({ "origin": origin.to_json(), "result": result }).stringify()
}

///|
fn render_skill_pages(
  pages : Array[Json],
  origin : String,
  json_output : Bool,
) -> String {
  if json_output {
    render_skill_result(origin, { "pages": pages.to_json() })
  } else {
    "[" + origin + "]\n" + render_pages(pages, false, "skills")
  }
}

///|
fn render_verified(
  held : @mcp_skills.HeldSkill,
  content : @mcp_skills.VerifiedContent,
  json_output : Bool,
) -> String raise {
  if json_output {
    Json::object({
      "origin": content.origin.to_json(),
      "skillUri": content.skill_uri.to_json(),
      "verified": true,
      "entry": held.entry(),
      "result": content.result,
    }).stringify()
  } else {
    "[" +
    content.origin +
    "] " +
    content.uri +
    " (consistency verified)\n" +
    @utf8.decode(content.bytes)
  }
}

///|
fn render_pages(
  pages : Array[Json],
  json_output : Bool,
  key : String,
) -> String {
  if json_output {
    return Json::object({ "pages": pages.to_json() }).stringify()
  }
  let lines : Array[String] = []
  for page in pages {
    if page is Object(fields) && fields.get(key) is Some(Array(items)) {
      for item in items {
        match item {
          {
            "uri": String(uri),
            "frontmatter": { "name": String(name), .. },
            ..
          }
          | { "uri": String(uri), "name": String(name), .. } =>
            lines.push(name + "\t" + uri)
          _ => ()
        }
      }
    }
  }
  lines.join("\n")
}

///|
fn render_resource(
  result : @mcp_skills.ReadResult,
  json_output : Bool,
) -> String {
  match result {
    Directory(pages) => render_pages(pages, json_output, "resources")
    Content(content) => {
      if json_output {
        return content.stringify()
      }
      guard content is { "contents": Array(contents), .. } else {
        return content.stringify()
      }
      contents
      .map(item => {
        match item {
          { "text": String(text), .. } => text
          _ => item.stringify()
        }
      })
      .join("\n")
    }
  }
}
