///|
test "search score: exact name match is highest" {
  let score = @search.server_search_score(
    "github",
    "github",
    Some("GitHub Issues and PRs"),
  )
  let other = @search.server_search_score("github", "gitlab", Some("GitLab"))
  inspect(score > other, content="true")
  inspect(score >= 100, content="true")
}

///|
test "search score: name prefix match" {
  let score = @search.server_search_score("git", "github", None)
  inspect(score >= 50, content="true")
}

///|
test "search score: name contains" {
  let score = @search.server_search_score("hub", "github", None)
  inspect(score >= 30, content="true")
  inspect(score < 100, content="true")
}

///|
test "search score: token exact match" {
  let score = @search.server_search_score(
    "review",
    "code-review-tool",
    Some("Code review automation"),
  )
  inspect(score >= 25, content="true")
}

///|
test "search score: token prefix match" {
  let score = @search.server_search_score(
    "code",
    "tools",
    Some("Use to review codebase"),
  )
  inspect(score >= 15, content="true")
}

///|
test "search score: position bonus — earlier match is higher" {
  let early = @search.server_search_score("git", "git-tools", None)
  let late = @search.server_search_score("git", "my-git-tools", None)
  inspect(early > late, content="true")
}

///|
test "search score: multi-word AND filter — partial match excluded" {
  let score = @search.server_search_score(
    "code review",
    "github",
    Some("GitHub code search"),
  )
  inspect(score == 0, content="true")
}

///|
test "search score: multi-word score accumulation" {
  let score = @search.server_search_score(
    "code review",
    "code-review-tool",
    Some("Automated code review for PRs"),
  )
  inspect(score > 0, content="true")
}

///|
test "search servers: sorted by score desc, then name asc" {
  let servers : Array[(String, String?)] = [
    ("gitlab", Some("GitLab code review")),
    ("github", Some("GitHub Issues and PRs")),
    ("playwright", Some("Browser automation")),
  ]
  let (results, _total) = @search.search_servers("git", servers)
  inspect(results.length() == 2, content="true")
  // Both gitlab and github match; same score → name asc → github first
  inspect(results[0].name == "github", content="true")
  inspect(results[1].name == "gitlab", content="true")
  // playwright excluded
}

///|
test "search servers: top 5 limit" {
  let servers : Array[(String, String?)] = Array::makei(8, i => {
    ("server-\{i}", Some("git tool number \{i}"))
  })
  let (results, _total) = @search.search_servers("git", servers)
  inspect(results.length() == 5, content="true")
}
