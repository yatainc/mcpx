///|
test "wasm: legacy calls preserve result data without modern result-type admission" {
  for result_type in ["input_required", "extension"] {
    let result : Json = { "resultType": result_type.to_json(), "value": "kept" }
    let host_result : Json = {
      "ok": true,
      "statusCode": 200,
      "contentType": "application/json",
      "body": Json::object({ "jsonrpc": "2.0", "id": 2, "result": result })
      .stringify()
      .to_json(),
    }
    inspect(
      mcpx_tool_reduce(
        (
          #|{"phase":"mcp_http_call","requestId":2}
        ),
        host_result.stringify(),
      ),
      content=Json::object({ "status": "ready", "result": result }).stringify(),
    )
  }
}
