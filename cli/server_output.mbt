///|
fn servers_result(
  servers : Map[String, @config.McpServerConfig],
  config_path : String,
) -> String {
  if servers.is_empty() {
    return "No servers configured.\nConfig: " + config_path
  }
  let lines = ["Servers:"]
  let mut width = 0
  for name, _ in servers {
    if name.length() > width {
      width = name.length()
    }
  }
  for name, server in servers {
    let summary = server.description.bind(text => {
      for line in text.split("\n") {
        let line = line.trim().to_owned()
        if !line.is_empty() {
          return Some(line)
        }
      }
      None
    })
    match summary {
      Some(summary) =>
        lines.push(
          "  " + pad_right(name, width) + "  " + truncate_chars(summary, 60),
        )
      None => lines.push("  " + name)
    }
  }
  lines.join("\n")
}

///|
fn pad_right(text : String, width : Int) -> String {
  let out = StringBuilder(size_hint=width)
  out.write_string(text)
  for _ in text.length()..<width {
    out.write_char(' ')
  }
  out.to_string()
}

///|
fn truncate_chars(text : String, max_chars : Int) -> String {
  let chars = text.to_array()
  if chars.length() <= max_chars {
    return text
  }
  let out = StringBuilder(size_hint=max_chars)
  if max_chars <= 3 {
    for _ in 0..<max_chars {
      out.write_char('.')
    }
  } else {
    for i in 0..<(max_chars - 3) {
      out.write_char(chars[i])
    }
    out.write_string("...")
  }
  out.to_string()
}
