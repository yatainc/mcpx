///|
suberror EnvTemplateError {
  MissingEnvVar(String)
  InvalidEnvVarSyntax(String)
} derive(Debug)

///|
pub impl Show for EnvTemplateError with fn output(self, logger) {
  match self {
    MissingEnvVar(name) => {
      logger.write_string("MissingEnvVar(\"")
      logger.write_string(name)
      logger.write_string("\")")
    }
    InvalidEnvVarSyntax(raw) => {
      logger.write_string("InvalidEnvVarSyntax(\"")
      logger.write_string(raw)
      logger.write_string("\")")
    }
  }
}

///|
pub fn resolve_env_template(
  input : String,
  env : Map[String, String],
  strict? : Bool = true,
) -> String raise EnvTemplateError {
  let view = input.to_string_view()
  let out = StringBuilder::new(size_hint=view.length())
  for i = 0; i < view.length(); {
    match (view.get_char(i), view.get_char(i + 1)) {
      (Some('$'), Some('{')) =>
        match find_closing_brace(view, i + 2) {
          None => raise InvalidEnvVarSyntax(input)
          Some(close) => {
            let name = view
              .view(start_offset=i + 2, end_offset=close)
              .to_owned()
            if !is_valid_env_name(name) {
              raise InvalidEnvVarSyntax(input)
            }
            match env.get(name) {
              Some(value) => out.write_string(value)
              None => if strict { raise MissingEnvVar(name) } else { () }
            }
            continue close + 1
          }
        }
      (Some(c), _) => {
        out.write_char(c)
        continue i + 1
      }
      (None, _) => break out.to_string()
    }
  } nobreak {
    out.to_string()
  }
}

///|
fn find_closing_brace(view : StringView, start : Int) -> Int? {
  for i in start..<view.length() {
    if view.get_char(i) == Some('}') {
      break Some(i)
    }
  } nobreak {
    None
  }
}

///|
fn is_valid_env_name(name : String) -> Bool {
  let chars = name.to_array()
  match chars.get(0) {
    Some(first) if is_env_name_start(first) => chars[1:].all(is_env_name_rest)
    _ => false
  }
}

///|
fn is_env_name_start(c : Char) -> Bool {
  c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn is_env_name_rest(c : Char) -> Bool {
  is_env_name_start(c) || (c >= '0' && c <= '9')
}
