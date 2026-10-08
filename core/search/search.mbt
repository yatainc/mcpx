///|
pub struct SearchResult {
  name : String
  description : String
  score : Int
} derive(Debug, Eq, Hash)

///|
pub extend SearchResult with Debug::{to_repr}

///|
pub extend SearchResult with Eq::{not_equal, equal}

///|
pub extend SearchResult with Hash::{hash, hash_combine}

///|
impl Compare for SearchResult with fn compare(self, other) {
  if self.score != other.score {
    other.score - self.score
  } else {
    self.name.compare(other.name)
  }
}

///|
pub fn server_search_score(
  query : String,
  name : String,
  description : String?,
) -> Int {
  let query_lower = query.to_lower()
  let name_lower = name.to_lower()
  let desc_lower = match description {
    Some(d) => d.to_lower()
    None => ""
  }
  let query_tokens = text_tokens(query_lower)
  if query_tokens.is_empty() {
    return 0
  }
  let name_tokens = text_tokens(name_lower)
  let desc_tokens = if desc_lower.length() > 0 {
    text_tokens(desc_lower)
  } else {
    []
  }
  // AND filter + token scoring in one pass
  let mut token_score = 0
  for q_token in query_tokens {
    let matched = name_lower.contains(q_token) ||
      desc_lower.contains(q_token) ||
      name_tokens.any(fn(t) { t.has_prefix(q_token) }) ||
      desc_tokens.any(fn(t) { t.has_prefix(q_token) })
    if !matched {
      return 0
    }
    token_score = token_score + token_match_score(q_token, name_tokens)
    token_score = token_score + token_match_score(q_token, desc_tokens)
  }
  let string_score = string_match_score(query_lower, name_lower) +
    string_match_score(query_lower, desc_lower)
  string_score + token_score
}

///|
pub fn search_servers(
  query : String,
  servers : Array[(String, String?)],
) -> (Array[SearchResult], Int) {
  let results = []
  for entry in servers {
    let (name, description) = entry
    let score = server_search_score(query, name, description)
    if score > 0 {
      results.push({ name, description: description.unwrap_or(""), score, })
    }
  }
  let total = results.length()
  results.sort()
  if results.length() > 5 {
    results.truncate(5)
  }
  (results, total)
}

///|
fn text_tokens(text : String) -> Array[String] {
  let tokens = []
  for part in text.split(" ") {
    let trimmed = part.trim().to_owned()
    if trimmed.length() == 0 {
      continue
    }
    for sub in trimmed.split("-") {
      let word = sub.trim().to_owned()
      if word.length() > 0 {
        tokens.push(word)
      }
    }
  }
  tokens
}

///|
fn string_match_score(query_lower : String, text : String) -> Int {
  if text.length() == 0 {
    return 0
  }
  if query_lower == text {
    100
  } else if text.has_prefix(query_lower) {
    50 + position_bonus(text, query_lower)
  } else if text.contains(query_lower) {
    30 + position_bonus(text, query_lower)
  } else {
    0
  }
}

///|
fn token_match_score(q_token : String, t_tokens : Array[String]) -> Int {
  let mut score = 0
  for t_token in t_tokens {
    if q_token == t_token {
      score = score + 25
    } else if t_token.has_prefix(q_token) {
      score = score + 15
    }
  }
  score
}

///|
fn position_bonus(text : String, needle : String) -> Int {
  match text.find(needle) {
    Some(pos) => 10 - pos * 10 / text.length()
    None => 0
  }
}
