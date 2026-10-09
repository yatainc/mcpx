///|
pub suberror VerificationError {
  VerificationError(
    origin~ : String,
    skill_uri~ : String,
    uri~ : String,
    reason~ : String
  )
}

///|
pub impl Show for VerificationError with fn output(self, logger) {
  let VerificationError(origin~, skill_uri~, uri~, reason~) = self
  logger.write_string(origin + " " + skill_uri + " [" + uri + "]: " + reason)
}

///|
pub extend VerificationError with Show::{output, to_string}

///|
/// Consistency-verified data, never approval or authority over the host.
pub struct VerifiedContent {
  origin : String
  skill_uri : String
  uri : String
  bytes : Bytes
  result : Json
}

///|
fn HeldSkill::failure(
  self : HeldSkill,
  uri : String,
  reason : String,
) -> VerificationError {
  VerificationError(origin=self.origin(), skill_uri=self.uri, uri~, reason~)
}

///|
fn digest(bytes : Bytes) -> String {
  "sha256:" + @hex.encode(Bytes::from_array(@crypto.sha256(bytes)[:]))
}

///|
/// Read only a manifest member against the original peer and entry.
/// Root frontmatter is checked; nested SKILL.md remains supporting bytes.
pub async fn HeldSkill::read(self : HeldSkill, uri : String) -> VerifiedContent {
  guard self.files.get(uri) is Some(file) else {
    raise self.failure(uri, "resource is not in the held manifest")
  }
  let result = read_content(self.source.call, uri)
  guard result is { "contents": [content], .. } &&
    content is { "uri": String(returned_uri), .. } &&
    returned_uri == uri else {
    raise self.failure(
      uri, "expected exactly one content with the requested URI",
    )
  }
  let bytes = match content {
    { "text": String(text), .. } => {
      // UTF-8 has at least one byte per UTF-16 code unit.
      if text.length() > file.size {
        raise self.failure(uri, "text exceeds the declared byte length")
      }
      @utf8.encode(text)
    }
    { "blob": String(blob), .. } => {
      if blob.length() > (file.size + 2) / 3 * 4 {
        raise self.failure(uri, "blob exceeds the declared byte length")
      }
      @base64.decode(blob) catch {
        _ => raise self.failure(uri, "invalid base64 resource")
      }
    }
    _ => raise self.failure(uri, "resource requires text or blob")
  }
  if bytes.length() != file.size {
    raise self.failure(uri, "byte length differs from the held entry")
  }
  if digest(bytes) != file.digest {
    raise self.failure(uri, "SHA-256 differs from the held entry")
  }
  if uri == self.uri {
    let frontmatter = parse_frontmatter(bytes) catch {
      _ =>
        raise self.failure(
          uri, "root requires valid bounded UTF-8 YAML frontmatter",
        )
    }
    guard self.entry is { "frontmatter": expected, .. } &&
      frontmatter == expected else {
      raise self.failure(uri, "frontmatter differs from the held entry")
    }
  }
  { origin: self.origin(), skill_uri: self.uri, uri, bytes, result, }
}
