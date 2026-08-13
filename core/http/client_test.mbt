///|
async test "core http: auto discovers then lists over MCP 2026" {
  let seen : Array[HttpRequest] = []
  let tools = list_tools(
    req => {
      seen.push(req)
      if rpc_method(req.body) == "server/discover" {
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"],"capabilities":{},"_meta":{"io.modelcontextprotocol/serverInfo":{"name":"mock","version":"1"}}}}
          ),
        )
      } else {
        http_response(
          status_code=200,
          content_type=Some("application/json"),
          body=(
            #|{"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","tools":[{"name":"search","inputSchema":{"type":"object"}}]}}
          ),
        )
      }
    },
    http_endpoint(url="https://mcp.example/mcp"),
  )
  inspect(tools[0].name, content="search")
  inspect(
    seen.map(req => rpc_method(req.body)).join(","),
    content="server/discover,tools/list",
  )
  inspect(header(seen[0].headers, "Mcp-Method"), content="server/discover")
  inspect(header(seen[1].headers, "Mcp-Method"), content="tools/list")
  inspect(header(seen[1].headers, "Mcp-Session-Id"), content="")
  inspect(seen[1].body.contains("\"initialize\""), content="false")
}

///|
fn rpc_method(body : String) -> String {
  let parsed = @json.parse(body) catch { _ => return "" }
  match parsed {
    Object(obj) =>
      match obj.get("method") {
        Some(String(value)) => value
        _ => ""
      }
    _ => ""
  }
}

///|
fn rpc_cursor(body : String) -> String {
  let parsed = @json.parse(body) catch { _ => return "" }
  match parsed {
    Object(obj) =>
      match obj.get("params") {
        Some(Object(params)) =>
          match params.get("cursor") {
            Some(String(value)) => value
            _ => ""
          }
        _ => ""
      }
    _ => ""
  }
}

///|
fn header(headers : Map[String, String], key : String) -> String {
  match headers.get(key) {
    Some(value) => value
    None => headers.get(key.to_lower()).unwrap_or("")
  }
}
