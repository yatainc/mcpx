///|
extern "js" fn make_mock_mcp_http_fetch() -> JsFetch =
  #| () => {
  #|   let n = 0;
  #|   return (_method, url, _headersJson, body) => new Promise((resolve) => {
  #|     n += 1;
  #|     if (n === 1) resolve(JSON.stringify({ statusCode: 400, contentType: null, headers: {}, body: "" }));
  #|     else if (n === 2) resolve(JSON.stringify({ statusCode: 200, contentType: "application/json", headers: {}, body: JSON.stringify({ jsonrpc: "2.0", id: 1, result: { protocolVersion: "2025-03-26", capabilities: {}, serverInfo: { name: "mock", version: "1" } } }) }));
  #|     else if (n === 3) resolve(JSON.stringify({ statusCode: 202, contentType: null, headers: {}, body: "{}" }));
  #|     else resolve(JSON.stringify({ statusCode: 200, contentType: "application/json", headers: {}, body: JSON.stringify({ jsonrpc: "2.0", id: 2, result: { tools: [{ name: "search", description: "Search", inputSchema: { type: "object" } }] } }) }));
  #|   });
  #| }

///|
async test "js mcp_http: list tools can use injected Promise fetch adapter" {
  let tools = list_tools_js(
    make_mock_mcp_http_fetch(),
    url="https://mcp.example/mcp",
  )
  inspect(tools.length(), content="1")
  inspect(tools[0].name, content="search")
}
