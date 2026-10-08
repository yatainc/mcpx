///|
test "jsonc: strips comments and trailing commas" {
  let input =
    #|{
    #|  // managed by user
    #|  "mcpServers": {
    #|    "github": {
    #|      "transport": "http",
    #|      "url": "https://mcp.github.com/mcp",
    #|    },
    #|  },
    #|}
  let normalized = @config.normalize_jsonc(input)
  let parsed = @json.parse(normalized)
  inspect(
    parsed.stringify(indent=2),
    content=(
      #|{
      #|  "mcpServers": {
      #|    "github": {
      #|      "transport": "http",
      #|      "url": "https://mcp.github.com/mcp"
      #|    }
      #|  }
      #|}
    ),
  )
}

///|
test "jsonc: preserves comment markers inside strings" {
  let input =
    #|{"url":"https://example.com/a//b","x":"/* not comment */"}
  inspect(
    @json.parse(@config.normalize_jsonc(input)).stringify(),
    content="{\"url\":\"https://example.com/a//b\",\"x\":\"/* not comment */\"}",
  )
}
