///|
async test "body exact overflow EOF and negative limits" {
  for
    (text, limit, accepted) in [
      ("abc", 3, true),
      ("abcd", 3, false),
      ("", 0, true),
      ("", -1, false),
    ] {
    let reader = @io.MemoryReader(writer => writer.write(text))
    defer reader.close()
    let ok = try {
      ignore(@receive.body(reader, @receive.Budget::new(), limit~))
      true
    } catch {
      _ => false
    }
    assert_eq(ok, accepted)
  }
}

///|
async test "line framing preserves a Unicode scalar split across asynchronous chunks" {
  let reader = @io.MemoryReader(writer => {
    writer.write(b"\xf0\x9f")
    @async.sleep(1)
    writer.write(b"\x98\x80\n")
  })
  defer reader.close()
  let lines = @receive.Lines::new(reader)
  assert_eq(lines.next(@receive.Budget::new()), Some(@utf8.encode("😀\n")))
}

///|
async test "line framing preserves leftovers UTF8 CRLF and cumulative budgets" {
  let reader = @io.MemoryReader(writer => writer.write("😀\r\na\nb"))
  defer reader.close()
  let lines = @receive.Lines::new(reader)
  let budget = @receive.Budget::new(limit=9)
  assert_eq(lines.next(budget, limit=6), Some(@utf8.encode("😀\r\n")))
  assert_eq(lines.next(budget), Some(b"a\n"))
  assert_eq(lines.next(budget), Some(b"b"))
  assert_eq(lines.next(budget), None)
  let reader = @io.MemoryReader(writer => writer.write("abc\nabc\n"))
  defer reader.close()
  let lines = @receive.Lines::new(reader)
  let budget = @receive.Budget::new(limit=7)
  assert_eq(lines.next(budget), Some(b"abc\n"))
  assert_true(
    try {
      ignore(lines.next(budget))
      false
    } catch {
      @receive.LimitExceeded(_) => true
      error => raise error
    },
  )
}
