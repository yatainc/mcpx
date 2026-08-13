///|
pub fn encode_mcp_http_header_value(value : String) -> String {
  if is_plain_mcp_http_header_value(value) {
    value
  } else {
    let bytes = @utf8.encode(value.to_string_view(), bom=false)
    "=?base64?" + @base64.encode(bytes, padding=true) + "?="
  }
}

///|
fn is_plain_mcp_http_header_value(value : String) -> Bool {
  if value.has_prefix("=?base64?") && value.has_suffix("?=") {
    return false
  }
  let mut first = true
  let mut last_is_whitespace = false
  for char in value {
    let code = char.to_int()
    if code != 0x09 && (code < 0x20 || code > 0x7e) {
      return false
    }
    let is_whitespace = code == 0x20 || code == 0x09
    if first && is_whitespace {
      return false
    }
    first = false
    last_is_whitespace = is_whitespace
  }
  !last_is_whitespace
}
