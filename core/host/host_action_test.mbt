///|
test "host action: private credentials write is atomic 0600" {
  let action = @host.host_write_private_text_file(
    path="/home/me/.config/mcpx/credentials.json",
    contents="{\"version\":1}",
  )
  inspect(
    action.to_json().stringify(),
    content=(
      #|{"kind":"write_text_file","path":"/home/me/.config/mcpx/credentials.json","contents":"{\"version\":1}","mode":384,"atomic":true,"createParentDirs":true}
    ),
  )
}

///|
test "host action: read text file is data only" {
  let action = @host.host_read_text_file(
    path="/home/me/.config/mcpx/credentials.json",
  )
  inspect(
    action.to_json().stringify(),
    content=(
      #|{"kind":"read_text_file","path":"/home/me/.config/mcpx/credentials.json"}
    ),
  )
}

///|
test "host action: open browser is explicit data action" {
  let action = @host.host_open_browser(url="http://127.0.0.1:9876/callback")
  inspect(
    action.to_json().stringify(),
    content=(
      #|{"kind":"open_browser","url":"http://127.0.0.1:9876/callback"}
    ),
  )
}
