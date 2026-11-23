///|
fn decode_sse_data(text : String) -> Array[String] {
  let normalized = text
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  let out = []
  let data_lines = []
  for line_view in normalized.split("\n") {
    let line = line_view.to_owned()
    if line.is_empty() {
      if !data_lines.is_empty() {
        out.push(data_lines.join("\n"))
        data_lines.clear()
      }
    } else if line.has_prefix("data:") {
      let mut rest = line.exact_view(start=5).to_owned()
      if rest.has_prefix(" ") {
        rest = rest.exact_view(start=1).to_owned()
      }
      data_lines.push(rest)
    }
  }
  if !data_lines.is_empty() {
    out.push(data_lines.join("\n"))
  }
  out
}
