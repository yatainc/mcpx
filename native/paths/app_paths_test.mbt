///|
test "mcpx app paths: default files under ~/.config/mcpx" {
  let paths = @paths.mcpx_app_paths("/Users/alice")
  inspect(paths.config_dir, content="/Users/alice/.config/mcpx")
  inspect(paths.servers_config, content="/Users/alice/.config/mcpx/mcp.jsonc")
  inspect(paths.env_file, content="/Users/alice/.config/mcpx/.env")
  inspect(
    paths.credentials_file,
    content="/Users/alice/.config/mcpx/credentials.json",
  )
}

///|
test "mcpx app paths: explicit config home wins over home" {
  let paths = @paths.mcpx_app_paths(
    "/Users/alice",
    config_home=Some("/tmp/xdg-config"),
  )
  inspect(paths.config_dir, content="/tmp/xdg-config/mcpx")
  inspect(paths.servers_config, content="/tmp/xdg-config/mcpx/mcp.jsonc")
  inspect(paths.env_file, content="/tmp/xdg-config/mcpx/.env")
  inspect(
    paths.credentials_file,
    content="/tmp/xdg-config/mcpx/credentials.json",
  )
}

///|
#cfg(not(platform="windows"))
test "mcpx app paths: absolute means absolute on the actual platform" {
  inspect(
    @paths.mcpx_app_paths(
      "/Users/alice",
      config_home=Some("C:/not-absolute-on-posix"),
    ).config_dir,
    content="/Users/alice/.config/mcpx",
  )
}

///|
#cfg(not(platform="windows"))
test "mcpx app paths: a literal trailing backslash is not a POSIX separator" {
  inspect(
    @paths.mcpx_app_paths("/Users/alice", config_home=Some("/tmp/config\\")).config_dir,
    content="/tmp/config\\/mcpx",
  )
  inspect(
    @paths.mcpx_app_paths(
      "/Users/alice",
      config_home=Some("/tmp/link/../config"),
    ).config_dir,
    content="/tmp/link/../config/mcpx",
  )
}

///|
test "mcpx app paths: empty or relative config home falls back to home" {
  inspect(
    @paths.mcpx_app_paths("/Users/alice", config_home=Some("")).config_dir,
    content="/Users/alice/.config/mcpx",
  )
  inspect(
    @paths.mcpx_app_paths("/Users/alice", config_home=Some("relative/config")).config_dir,
    content="/Users/alice/.config/mcpx",
  )
}
