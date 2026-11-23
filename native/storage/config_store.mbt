///|
pub fn load_mcpx_config_or_empty(path : String) -> @config.McpxConfig raise {
  if @fs.path_exists(path) {
    let text = @fs.read_file_to_string(path)
    let normalized = @config.normalize_jsonc(text)
    @config.decode_mcpx_config(@json.parse(normalized))
  } else {
    @config.empty_mcpx_config()
  }
}

///|
pub fn save_mcpx_config_file(
  path : String,
  config : @config.McpxConfig,
) -> Unit raise {
  secure_write_private_atomic(path, config.to_json().stringify())
}

///|
pub fn mcpx_config_file_mode(path : String) -> Int32 raise {
  secure_file_mode(path)
}
