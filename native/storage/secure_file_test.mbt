///|
test "secure file: atomic private write creates parents and 0600 file" {
  let path = "/tmp/mcpx-secure-file-test/nested/credentials.json"
  @fs.remove_file(path) catch {
    _ => ()
  }
  @storage.secure_write_private_atomic(path, "{\"version\":1}")
  inspect(@fs.read_file_to_string(path), content="{\"version\":1}")
  inspect(@storage.secure_file_mode(path), content="384")
}

///|
test "secure file: overwrite keeps private mode and replaces content" {
  let path = "/tmp/mcpx-secure-file-test/nested/credentials.json"
  @storage.secure_write_private_atomic(path, "old")
  @storage.secure_write_private_atomic(path, "new")
  inspect(@fs.read_file_to_string(path), content="new")
  inspect(@storage.secure_file_mode(path), content="384")
}
