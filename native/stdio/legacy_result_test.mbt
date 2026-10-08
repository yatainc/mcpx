///|
#cfg(all(target="native", not(platform="windows")))
async test "mcp stdio: legacy calls preserve result data without modern result-type admission" {
  for result_type in ["input_required", "extension"] {
    let script = (
      #|i=0
      #|while IFS= read -r line; do
      #|  i=$((i + 1))
      #|  if [ "$i" = "1" ]; then
      #|    printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25"}}'
      #|  elif [ "$i" = "3" ]; then
      #|    printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"resultType":"RESULT_TYPE","value":"kept"}}'
      #|  fi
      #|done
    ).replace_all(old="RESULT_TYPE", new=result_type)
    let result = @stdio.stdio_mcp_call_tool(
      command="/bin/sh",
      args=["-c", script],
      env=Map([]),
      cwd=None,
      tool_name="echo",
      arguments={},
    )
    json_inspect(result, content={
      "resultType": result_type.to_json(),
      "value": "kept",
    })
  }
}
