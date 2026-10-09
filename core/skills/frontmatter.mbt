///|
fn frontmatter_text(source : String) -> String raise {
  let source = source.strip_prefix("﻿").unwrap_or(source[:])
  guard source.split_once("\n") is Some((opening, contents)) &&
    opening.trim_end() == "---" else {
    fail("missing frontmatter opening")
  }
  let mut rest = contents
  for ;; {
    let (line, next) = match rest.split_once("\n") {
      Some(parts) => parts
      None => (rest, "")
    }
    if line.trim_end() == "---" {
      return contents[:contents.length() - rest.length()].to_owned()
    }
    if next.is_empty() {
      fail("missing frontmatter closing")
    }
    rest = next
  }
}

///|
fn parse_frontmatter(bytes : Bytes) -> Json raise {
  let documents = @yaml.Yaml::load_from_string(
    frontmatter_text(@utf8.decode(bytes)),
  )
  guard documents is [document] else { fail("expected one YAML document") }
  let value = yaml_json(
    document,
    { nodes: 1_000_000, bytes: 96 * 1024 * 1024, },
    0,
  )
  guard value is { "name": String(_), "description": String(_), .. } else {
    fail("frontmatter requires name and description")
  }
  value
}

///|
priv struct YamlBudget {
  mut nodes : Int
  mut bytes : Int
}

///|
fn YamlBudget::spend(self : YamlBudget, bytes : Int) -> Unit raise {
  self.nodes -= 1
  self.bytes -= bytes
  if self.nodes < 0 || self.bytes < 0 {
    fail("YAML conversion limit")
  }
}

///|
// YAML can be a cyclic/shared graph. Never call recursive graph to_json().
// Only scalar conversion is delegated to the parser's standard JSON conversion.
fn yaml_json(
  value : @yaml.Yaml,
  budget : YamlBudget,
  depth : Int,
) -> Json raise {
  if depth > 128 {
    fail("YAML depth or cycle")
  }
  budget.spend(2)
  match value {
    Array(items) => {
      let out = []
      for item in items {
        out.push(yaml_json(item, budget, depth + 1))
      }
      Json::array(out)
    }
    Map(fields) => {
      let out = Map([])
      for key, item in fields {
        budget.spend(@utf8.encode(key.to_json().stringify()).length() + 1)
        out[key] = yaml_json(item, budget, depth + 1)
      }
      Json::object(out)
    }
    BadValue => fail("unrepresentable YAML")
    Real(number, ..) if number.is_inf() || number.is_nan() =>
      fail("non-JSON number")
    _ => {
      let out = value.to_json()
      budget.spend(@utf8.encode(out.stringify()).length())
      out
    }
  }
}

///|
// Constant syntax, not untrusted input. Unicode categories come from the
// official regexp library rather than a hand-written character table.
let invalid_name_character : @regexp.Regexp = try! @regexp.compile(
  "[^\\p{L}\\p{N}-]",
)

///|
fn require_frontmatter(value : Json) -> Unit raise @protocol.McpProtocolError {
  guard value
    is { "name": String(name), "description": String(description), .. } else {
    raise InvalidResponse("frontmatter requires name and description")
  }
  let length = name.iter().count()
  if length < 1 ||
    length > 64 ||
    name.has_prefix("-") ||
    name.has_suffix("-") ||
    name.contains("--") ||
    invalid_name_character.match_(name) is Some(_) ||
    !name.iter().all(c => @unicode.to_lowercase(c) == c) {
    raise InvalidResponse(
      "Skill name requires 1–64 lowercase alphanumeric characters and single hyphens",
    )
  }
  let length = description.iter().count()
  if length < 1 || length > 1024 {
    raise InvalidResponse("Skill description requires 1–1024 characters")
  }
  guard value is Object(fields) else {
    raise InvalidResponse("frontmatter requires object")
  }
  for key in ["license", "compatibility", "allowed-tools"] {
    if fields.get(key) is Some(value) {
      guard value is String(text) else {
        raise InvalidResponse(key + " requires a string")
      }
      if key == "compatibility" &&
        (text.iter().count() < 1 || text.iter().count() > 500) {
        raise InvalidResponse("compatibility requires 1–500 characters")
      }
    }
  }
  if fields.get("metadata") is Some(metadata) {
    guard metadata is Object(fields) &&
      fields.values().all(value => value is String(_)) else {
      raise InvalidResponse("metadata requires string keys and string values")
    }
  }
}
