///|
/// A fixed RPC peer. The host supplies a unique origin, not serverInfo.name.
/// Custom transports own receive limits, locking and cancellation.
pub struct Source {
  priv origin : String
  priv capabilities : Json
  priv call : async (String, Map[String, Json]) -> Json
}

///|
pub fn Source::new(
  origin : String,
  capabilities~ : Json,
  call~ : async (String, Map[String, Json]) -> Json,
) -> Source raise {
  if origin.is_empty() {
    raise @protocol.InvalidResponse("Skill source requires a nonempty origin")
  }
  require_skills(capabilities)
  { origin, capabilities: copy_json(capabilities), call, }
}

///|
fn copy_json(value : Json) -> Json raise {
  @json.parse(value.stringify())
}

///|
/// Get and own an entry without fetching any files or granting approval.
pub async fn Source::hold(self : Source, uri : String) -> HeldSkill {
  let result = get(self.call, capabilities=self.capabilities, uri~)
  guard result is { "skill": entry, .. } else {
    raise @protocol.InvalidResponse("skills/get requires skill")
  }
  hold_entry(self, copy_json(entry))
}

///|
priv struct File {
  digest : String
  size : Int
}

///|
/// Immutable entry ownership and fixed-source reads; not approval or activation.
pub struct HeldSkill {
  priv source : Source
  priv entry : Json
  priv uri : String
  priv files : Map[String, File]
}

///|
pub fn HeldSkill::origin(self : HeldSkill) -> String {
  self.source.origin
}

///|
pub fn HeldSkill::uri(self : HeldSkill) -> String {
  self.uri
}

///|
/// Return an independent copy; callers cannot change the held frontmatter.
pub fn HeldSkill::entry(self : HeldSkill) -> Json raise {
  copy_json(self.entry)
}

///|
/// Compare the content-bound identity, without fetching or changing either entry.
pub fn HeldSkill::same_content(self : HeldSkill, other : HeldSkill) -> Bool {
  if self.origin() != other.origin() ||
    self.uri != other.uri ||
    self.files.length() != other.files.length() {
    return false
  }
  for uri, file in self.files {
    guard other.files.get(uri) is Some(candidate) &&
      file.digest == candidate.digest else {
      return false
    }
  }
  true
}

///|
fn require_path(path : @uri.EStr[@uri_enc.IPath]) -> Unit raise {
  for segment in path.split('/') {
    let decoded = segment.decode_to_string()
    if decoded == "." || decoded == ".." {
      raise @protocol.InvalidResponse("Skill URI contains a dot segment")
    }
  }
}

///|
fn hold_entry(source : Source, entry : Json) -> HeldSkill raise {
  let uri = require_skill(entry)
  guard entry
    is { "frontmatter": frontmatter, "resources": Array(resources), .. } else {
    raise @protocol.InvalidResponse(
      "dynamic Skills cannot hold a verified manifest",
    )
  }
  if resources.length() > 512 {
    raise @protocol.InvalidResponse("Skill exceeds 512 resources")
  }
  require_frontmatter(frontmatter)
  guard frontmatter is { "name": String(name), .. } else {
    raise @protocol.InvalidResponse("frontmatter requires name")
  }
  let root = @uri.Iri::parse(uri)
  require_path(root.path)
  guard root.path.rsplit_once('/') is Some((directory, filename)) &&
    filename.as_str() == "SKILL.md" else {
    raise @protocol.InvalidResponse(
      "Skill URI must explicitly end in /SKILL.md",
    )
  }
  let folder_name = if directory.is_empty() {
    guard root.authority is Some(authority) &&
      !authority.has_userinfo() &&
      !authority.has_port() &&
      authority.host_parsed is RegName(segment) else {
      raise @protocol.InvalidResponse("Skill URI requires a named directory")
    }
    segment.decode_to_string()
  } else {
    let segment = directory
      .rsplit_once('/')
      .map(pair => pair.1)
      .unwrap_or(directory)
    segment.decode_to_string()
  }
  if folder_name != name {
    raise @protocol.InvalidResponse("Skill name must match its directory")
  }
  let prefix = directory.as_str() + "/"
  let files = Map([])
  let mut remaining = 16 * 1024 * 1024
  for resource in resources {
    guard resource
      is {
        "uri": String(file_uri),
        "digest": String(digest),
        "size": Number(size, ..),
        ..
      } else {
      raise @protocol.InvalidResponse("invalid Skill resource")
    }
    if files.contains(file_uri) {
      raise @protocol.InvalidResponse("duplicate Skill resource URI")
    }
    let file = @uri.Iri::parse(file_uri)
    require_path(file.path)
    if file.scheme != root.scheme ||
      file.authority.map(a => a.as_str()) != root.authority.map(a => a.as_str()) ||
      !file.path.as_str().has_prefix(prefix) ||
      file.path.as_str().has_suffix("/") {
      raise @protocol.InvalidResponse(
        "resource must be a file in the Skill directory",
      )
    }
    if size > remaining.to_double() {
      raise @protocol.InvalidResponse("Skill exceeds 16 MiB total file size")
    }
    let size = size.to_int()
    remaining -= size
    files[file_uri] = { digest, size, }
  }
  if !files.contains(uri) {
    raise @protocol.InvalidResponse("Skill manifest omits its root")
  }
  { source, entry, uri, files, }
}
