///|
async test "core http: legacy calls preserve result data without modern result-type admission" {
  for result_type in ["input_required", "extension"] {
    let result = call_tool(
      request => {
        match @json.parse(request.body) {
          { "method": String("initialize"), .. } =>
            http_response(
              status_code=200,
              body=Json::object({
                "jsonrpc": "2.0",
                "id": 1,
                "result": { "protocolVersion": "2025-11-25" },
              }).stringify(),
            )
          { "method": String("notifications/initialized"), .. } =>
            http_response(status_code=202, body="")
          _ =>
            http_response(
              status_code=200,
              body=Json::object({
                "jsonrpc": "2.0",
                "id": 2,
                "result": {
                  "resultType": result_type.to_json(),
                  "value": "kept",
                },
              }).stringify(),
            )
        }
      },
      http_endpoint(url="https://example.test/mcp", mode=Stateful),
      tool_name="echo",
      arguments={},
    )
    json_inspect(result, content={
      "resultType": result_type.to_json(),
      "value": "kept",
    })
  }
}
