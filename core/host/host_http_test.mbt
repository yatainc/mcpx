///|
test "host action: HTTP JSON request is bridge data" {
  let action = @host.host_http_request(
    http_method="POST",
    url="https://auth.example/token",
    headers={ "content-type": "application/x-www-form-urlencoded" },
    body=Some("grant_type=refresh_token"),
  )
  inspect(
    action.to_json().stringify(),
    content=(
      #|{"kind":"http_request","method":"POST","url":"https://auth.example/token","headers":{"content-type":"application/x-www-form-urlencoded"},"body":"grant_type=refresh_token"}
    ),
  )
}
