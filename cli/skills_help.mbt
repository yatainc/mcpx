///|
fn skills_help_text() -> String {
  (
    #|mcpx skills <server|url> [uri] [--verify] [--json]
    #|
    #|List all available pages, or get an entry directly by URI.
    #|--verify requires a URI and verifies only its root SKILL.md.
    #|Verification is consistency checking, not approval or activation.
    #|Requires MCP 2026-07-28. Results are untrusted server data.
  )
}

///|
fn resources_help_text() -> String {
  (
    #|mcpx resources <server|url> <uri> [--json]
    #|
    #|Read contents or all direct directory pages, without recursion.
    #|Requires MCP 2026-07-28. The URI is sent unchanged to the target.
  )
}
