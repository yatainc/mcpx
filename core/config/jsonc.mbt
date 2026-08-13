///|
suberror JsoncError {
  UnterminatedBlockComment
  UnterminatedString
} derive(Debug)

///|
pub fn normalize_jsonc(input : String) -> String raise JsoncError {
  let no_comments = strip_jsonc_comments(input)
  strip_jsonc_trailing_commas(no_comments)
}

///|
fn strip_jsonc_comments(input : String) -> String raise JsoncError {
  let view = input.to_string_view()
  let out = StringBuilder::new(size_hint=view.length())
  for i = 0, state = JsoncCommentState::Code, escape = false; i < view.length(); {
    let c = view.get_char(i).unwrap()
    match state {
      Code =>
        if c == '"' {
          out.write_char(c)
          continue i + 1, InString, false
        } else if c == '/' {
          match view.get_char(i + 1) {
            Some('/') => continue i + 2, LineComment, false
            Some('*') => continue i + 2, BlockComment, false
            _ => {
              out.write_char(c)
              continue i + 1, state, false
            }
          }
        } else {
          out.write_char(c)
          continue i + 1, state, false
        }
      InString => {
        out.write_char(c)
        if escape {
          continue i + 1, state, false
        } else if c == '\\' {
          continue i + 1, state, true
        } else if c == '"' {
          continue i + 1, Code, false
        } else {
          continue i + 1, state, false
        }
      }
      LineComment =>
        if c == '\n' {
          out.write_char(c)
          continue i + 1, Code, false
        } else {
          continue i + 1, state, false
        }
      BlockComment =>
        if c == '\n' {
          out.write_char(c)
          continue i + 1, state, false
        } else if c == '*' {
          match view.get_char(i + 1) {
            Some('/') => continue i + 2, Code, false
            _ => continue i + 1, state, false
          }
        } else {
          continue i + 1, state, false
        }
    }
  } nobreak {
    match state {
      BlockComment => raise UnterminatedBlockComment
      InString => raise UnterminatedString
      _ => ()
    }
    out.to_string()
  }
}

///|
fn strip_jsonc_trailing_commas(input : String) -> String raise JsoncError {
  let view = input.to_string_view()
  let out = StringBuilder::new(size_hint=view.length())
  for i = 0, in_string = false, escape = false; i < view.length(); {
    let c = view.get_char(i).unwrap()
    if in_string {
      out.write_char(c)
      if escape {
        continue i + 1, in_string, false
      } else if c == '\\' {
        continue i + 1, in_string, true
      } else if c == '"' {
        continue i + 1, false, false
      } else {
        continue i + 1, in_string, false
      }
    } else if c == '"' {
      out.write_char(c)
      continue i + 1, true, false
    } else if c == ',' {
      if is_jsonc_trailing_comma(view, i) {
        continue i + 1, in_string, false
      } else {
        out.write_char(c)
        continue i + 1, in_string, false
      }
    } else {
      out.write_char(c)
      continue i + 1, in_string, false
    }
  } nobreak {
    if in_string {
      raise UnterminatedString
    }
    out.to_string()
  }
}

///|
fn is_jsonc_trailing_comma(view : StringView, comma_index : Int) -> Bool {
  for i in (comma_index + 1)..<view.length() {
    match view.get_char(i).unwrap() {
      ' ' | '\t' | '\r' | '\n' => ()
      ']' | '}' => break true
      _ => break false
    }
  } nobreak {
    false
  }
}

///|
priv enum JsoncCommentState {
  Code
  InString
  LineComment
  BlockComment
}
