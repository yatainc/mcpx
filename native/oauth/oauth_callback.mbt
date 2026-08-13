///|
pub suberror OAuthCallbackError {
  Timeout
  StateMismatch
  MissingCode
  InvalidRequest
} derive(Debug)

///|
pub struct OAuthCallbackCode {
  code : String
  state : String
  issuer : String?
} derive(Debug)

///|
pub async fn open_authorization_url(url : String) -> Unit {
  match @sys.get_env_var("MCPX_BROWSER") {
    Some("fetch") => ignore(@http.get(url) catch { _ => return () })
    Some("none") => ()
    _ => {
      let opened = @process.spawn_orphan("open", [url]) catch {
        _ => @process.spawn_orphan("xdg-open", [url]) catch { _ => return () }
      }
      ignore(opened)
    }
  }
}

///|
pub async fn wait_for_oauth_callback(
  port~ : Int,
  path~ : String,
  expected_state~ : String,
  timeout_ms~ : Int,
  trigger~ : async (String) -> Unit,
) -> OAuthCallbackCode raise OAuthCallbackError {
  let captured : Ref[Result[OAuthCallbackCode, OAuthCallbackError]?] = Ref(None)
  let result : Result[OAuthCallbackCode, OAuthCallbackError] = @async.with_task_group(group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:\{port}"))
      defer server.close()
      let actual_port = server.addr.port()
      let redirect_uri = "http://127.0.0.1:\{actual_port}" + path
      group.spawn_bg(no_wait=true, () => {
        server.run_forever(allow_failure=true, (request, _body, conn) => {
          let parsed = parse_oauth_callback_path(
            request.path,
            path~,
            expected_state~,
          )
          captured.val = Some(parsed)
          match parsed {
            Ok(_) => {
              conn.send_response(200, "OK", extra_headers={
                "content-type": "text/plain",
              })
              conn
              ..write("OAuth complete. You can close this window.")
              .end_response()
            }
            Err(_) => {
              conn.send_response(400, "Bad Request", extra_headers={
                "content-type": "text/plain",
              })
              conn..write("OAuth callback rejected.").end_response()
            }
          }
          server.close()
        })
      })
      group.spawn_bg(no_wait=true, () => trigger(redirect_uri) catch { _ => () })
      try wait_for_callback_result(captured, timeout_ms~) |> Ok catch {
        e => Err(e)
      }
    },
  ) catch {
    _ => Err(Timeout)
  }
  match result {
    Ok(value) => value
    Err(error) => raise error
  }
}

///|
fn parse_oauth_callback_path(
  request_path : String,
  path~ : String,
  expected_state~ : String,
) -> Result[OAuthCallbackCode, OAuthCallbackError] {
  let query = if request_path == path {
    ""
  } else if request_path.has_prefix(path + "?") {
    request_path
    .to_string_view()
    .view(start_offset=path.length() + 1)
    .to_owned()
  } else {
    return Err(InvalidRequest)
  }
  let params = query_params(query)
  let state = params.get("state").unwrap_or("")
  if state != expected_state {
    return Err(StateMismatch)
  }
  let code = match params.get("code") {
    Some(value) if !value.is_empty() => value
    _ => return Err(MissingCode)
  }
  let decoded_code = percent_decode(code) catch { error => return Err(error) }
  let issuer = match params.get("iss") {
    Some(value) =>
      Some(percent_decode(value) catch { error => return Err(error) })
    None => None
  }
  Ok({ code: decoded_code, state, issuer })
}

///|
fn percent_decode(value : String) -> String raise OAuthCallbackError {
  let chars = value.to_array()
  let bytes : Array[Byte] = []
  for i = 0; i < chars.length(); {
    if chars[i] == '%' {
      guard i + 2 < chars.length() else { raise InvalidRequest }
      match (hex_value(chars[i + 1]), hex_value(chars[i + 2])) {
        (Some(high), Some(low)) => {
          bytes.push((high * 16 + low).to_byte())
          continue i + 3
        }
        _ => raise InvalidRequest
      }
    }
    if chars[i] == '+' {
      bytes.push((32 : Int).to_byte())
    } else {
      let encoded = @encoding.encode(UTF8, chars[i].to_string())
      for byte in encoded {
        bytes.push(byte)
      }
    }
    continue i + 1
  }
  let encoded = Bytes::from_array(bytes)
  @encoding.decoder(UTF8).decode(encoded[:]) catch {
    _ => raise InvalidRequest
  }
}

///|
fn hex_value(value : Char) -> Int? {
  match value {
    '0'..='9' => Some(value.to_int() - '0'.to_int())
    'a'..='f' => Some(value.to_int() - 'a'.to_int() + 10)
    'A'..='F' => Some(value.to_int() - 'A'.to_int() + 10)
    _ => None
  }
}

///|
fn query_params(query : String) -> Map[String, String] {
  let params = Map([])
  if query.is_empty() {
    return params
  }
  for part_view in query.split("&") {
    let part = part_view.to_owned()
    match part.split_once("=") {
      Some((key, value)) => params[key.to_owned()] = value.to_owned()
      None => ()
    }
  }
  params
}

///|
async fn wait_for_callback_result(
  captured : Ref[Result[OAuthCallbackCode, OAuthCallbackError]?],
  timeout_ms~ : Int,
) -> OAuthCallbackCode raise OAuthCallbackError {
  let deadline = @sys.now().reinterpret_as_int64() + timeout_ms.to_int64()
  for ;; {
    match captured.val {
      Some(Ok(value)) => break value
      Some(Err(error)) => raise error
      None =>
        if @sys.now().reinterpret_as_int64() >= deadline {
          raise Timeout
        } else {
          @async.sleep(10) catch {
            _ => raise Timeout
          }
        }
    }
  }
}
