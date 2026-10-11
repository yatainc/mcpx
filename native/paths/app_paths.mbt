///|
pub struct McpxAppPaths {
  config_dir : String
  // Default write location. Runtime file discovery belongs to the CLI.
  servers_config : String
  env_file : String
  credentials_file : String
}

///|
pub fn mcpx_app_paths(
  home : String,
  config_home? : String? = None,
) -> McpxAppPaths {
  let base = match config_home {
    Some(path) if @path.Path(path).is_absolute() => path
    _ => join_path(home, ".config")
  }
  let config_dir = join_path(base, "mcpx")
  {
    config_dir,
    servers_config: join_path(config_dir, "mcp.jsonc"),
    env_file: join_path(config_dir, ".env"),
    credentials_file: join_path(config_dir, "credentials.json"),
  }
}

///|
fn join_path(base : String, child : String) -> String {
  // Path::join normalizes symlink/.. lexically; keep filesystem components.
  let sep = @path.sep.to_string()
  base + (if base.has_suffix(sep) { "" } else { sep }) + child
}
