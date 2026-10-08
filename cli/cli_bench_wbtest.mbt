///|
test "bench cli parse configured call" (it : @bench.T) {
  let args = ["call", "github", "search", "{\"q\":\"moonbit\"}"]
  it.bench(() => {
    match parse_mcpx_args(args) {
      Ok(command) => it.keep(command)
      Err(_) => abort("unexpected parse error")
    }
  })
}

///|
test "bench cli parse direct URL call" (it : @bench.T) {
  let args = [
    "call", "https://mcp.example.test/mcp", "search", "{\"q\":\"moonbit\"}",
  ]
  it.bench(() => {
    match parse_mcpx_args(args) {
      Ok(command) => it.keep(command)
      Err(_) => abort("unexpected parse error")
    }
  })
}
