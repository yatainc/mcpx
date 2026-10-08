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
