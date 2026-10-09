///|
pub suberror LimitExceeded {
  LimitExceeded(String)
}

///|
pub impl Show for LimitExceeded with fn output(self, logger) {
  let LimitExceeded(message) = self
  logger.write_string(message)
}

///|
pub extend LimitExceeded with Show::{output, to_string}

///|
/// Shared only for one finite operation; never a reusable client's lifetime.
pub struct Budget {
  priv mut remaining : Int
}

///|
pub fn Budget::new(limit? : Int = 256 * 1024 * 1024) -> Budget raise {
  if limit < 0 {
    raise LimitExceeded("negative receive limit")
  }
  { remaining: limit, }
}

///|
fn Budget::spend(self : Budget, size : Int) -> Unit raise {
  if size > self.remaining {
    raise LimitExceeded("cumulative receive limit")
  }
  self.remaining -= size
}

///|
pub async fn body(
  reader : &@io.Reader,
  budget : Budget,
  limit? : Int = 128 * 1024 * 1024,
) -> Bytes {
  if limit < 0 || budget.remaining < 0 {
    raise LimitExceeded("negative receive limit")
  }
  let out = @buffer.Buffer()
  for ;; {
    let remaining = (limit - out.length()).min(budget.remaining)
    guard reader.read_some(max_len=remaining.min(32767) + 1) is Some(chunk) else {
      break
    }
    if chunk.length() > remaining {
      raise LimitExceeded("response body receive limit")
    }
    budget.spend(chunk.length())
    out.write_bytes(chunk)
  }
  out.to_bytes()
}

///|
/// Byte framing preserves chunk leftovers and decodes UTF-8 only after a frame.
pub struct Lines {
  priv reader : &@io.Reader
  priv mut pending : Bytes
  priv mut start : Int
}

///|
pub fn Lines::new(reader : &@io.Reader) -> Lines {
  { reader, pending: b"", start: 0, }
}

///|
pub async fn Lines::next(
  self : Lines,
  budget : Budget,
  limit? : Int = 128 * 1024 * 1024,
) -> Bytes? {
  if limit < 0 || budget.remaining < 0 {
    raise LimitExceeded("negative receive limit")
  }
  let out = @buffer.Buffer()
  for ;; {
    if self.start == self.pending.length() {
      let remaining = (limit - out.length()).min(budget.remaining)
      guard self.reader.read_some(max_len=remaining.min(32767) + 1)
        is Some(chunk) else {
        return if out.is_empty() { None } else { Some(out.to_bytes()) }
      }
      self.pending = chunk
      self.start = 0
    }
    let pending = self.pending[self.start:]
    let count = pending.find(b"\n").map(i => i + 1).unwrap_or(pending.length())
    if count > limit - out.length() {
      raise LimitExceeded("stdio frame receive limit")
    }
    budget.spend(count)
    out.write_bytes(pending[:count])
    let complete = pending[count - 1] == b'\n'
    self.start += count
    if complete {
      return Some(out.to_bytes())
    }
  }
}
