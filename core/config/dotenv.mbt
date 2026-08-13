///|
pub(all) enum DotenvError {
  InvalidDotenvLine(Int, String)
} derive(Debug)

///|
pub fn parse_dotenv(text : String) -> Result[Map[String, String], DotenvError] {
  let env : Map[String, String] = Map([])
  let mut line_number = 1
  for line_view in text.split("\n") {
    let line = line_view.trim().to_owned()
    if line == "" || line.has_prefix("#") {
      line_number = line_number + 1
      continue
    }
    match parse_dotenv_line(line) {
      Some((key, value)) => env[key] = value
      None => return Err(InvalidDotenvLine(line_number, line))
    }
    line_number = line_number + 1
  }
  Ok(env)
}

///|
pub fn merge_env(
  file_env : Map[String, String],
  process_env : Map[String, String],
) -> Map[String, String] {
  let merged = file_env.copy()
  for key, value in process_env {
    merged[key] = value
  }
  merged
}

///|
fn parse_dotenv_line(line : String) -> (String, String)? {
  match line.split_once("=") {
    None => None
    Some((key_view, value_view)) => {
      let key = key_view.trim().to_owned()
      if !is_dotenv_name(key) {
        None
      } else {
        Some((key, unquote_dotenv_value(value_view.trim().to_owned())))
      }
    }
  }
}

///|
fn unquote_dotenv_value(value : String) -> String {
  if value.length() >= 2 &&
    (
      (value.has_prefix("\"") && value.has_suffix("\"")) ||
      (value.has_prefix("'") && value.has_suffix("'"))
    ) {
    value
    .to_string_view()
    .view(start_offset=1, end_offset=value.length() - 1)
    .to_owned()
  } else {
    value
  }
}

///|
fn is_dotenv_name(name : String) -> Bool {
  let chars = name.to_array()
  match chars.get(0) {
    Some(first) if is_dotenv_name_start(first) =>
      chars[1:].all(is_dotenv_name_rest)
    _ => false
  }
}

///|
fn is_dotenv_name_start(c : Char) -> Bool {
  c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn is_dotenv_name_rest(c : Char) -> Bool {
  is_dotenv_name_start(c) || (c >= '0' && c <= '9')
}
