///|
async fn resolve_oauth_metadata(
  server_name~ : String,
  server_url~ : String?,
  metadata_url~ : String?,
) -> Result[@auth.OAuthMetadata, String] {
  match metadata_url {
    Some(url) => fetch_oauth_metadata(url)
    None => {
      let url = match server_url {
        Some(value) => value
        None => return Err("OAuth metadata URL is required: " + server_name)
      }
      match discover_oauth_metadata(url) {
        Ok(value) => Ok(value)
        Err("OAuth metadata issuer mismatch") =>
          Err("OAuth metadata issuer mismatch")
        Err(_) => Err("OAuth metadata URL is required: " + server_name)
      }
    }
  }
}

///|
async fn discover_oauth_metadata(
  server_url : String,
) -> Result[@auth.OAuthMetadata, String] {
  let (response, _data) = @http.get(server_url) catch {
    _ => return Err("failed to connect to server")
  }
  let www_auth = match http_header(response.headers, "www-authenticate") {
    Some(value) => value
    None => return Err("no www-authenticate header")
  }
  let resource_url = match parse_www_authenticate_resource_metadata(www_auth) {
    Some(value) => value
    None => return Err("no resource_metadata in www-authenticate")
  }
  let (res, res_data) = @http.get(resource_url, headers={
    "accept": "application/json",
  }) catch {
    _ => return Err("failed to fetch resource metadata")
  }
  if res.code != 200 {
    return Err("failed to fetch resource metadata")
  }
  let res_json = res_data.json() catch {
    _ => return Err("invalid resource metadata")
  }
  let auth_servers = match decode_authorization_servers(res_json) {
    Some(value) => value
    None => return Err("no authorization_servers in resource metadata")
  }
  let issuer = match auth_servers.get(0) {
    Some(value) => value
    None => return Err("empty authorization_servers")
  }
  fetch_oauth_metadata(
    oauth_authorization_server_metadata_url(issuer),
    expected_issuer=Some(issuer),
  )
}

///|
fn http_header(headers : Map[String, String], name : String) -> String? {
  match headers.get(name) {
    Some(value) => Some(value)
    None =>
      for key, value in headers {
        if key.equal_ignore_ascii_case(name) {
          break Some(value)
        }
      } nobreak {
        None
      }
  }
}

///|
fn parse_www_authenticate_resource_metadata(header : String) -> String? {
  let marker = "resource_metadata=\""
  let start = match header.to_lower().find(marker) {
    Some(pos) => pos + marker.length()
    None => return None
  }
  let rest = header.to_string_view().view(start_offset=start)
  let end = match rest.find("\"") {
    Some(pos) => pos
    None => return None
  }
  match rest.get_view(start=0, end~) {
    Some(value) => Some(value.to_owned())
    None => None
  }
}

///|
fn decode_authorization_servers(json : Json) -> Array[String]? {
  match json {
    Object(obj) =>
      match obj.get("authorization_servers") {
        Some(Array(servers)) => {
          let urls = []
          for server in servers {
            match server {
              String(url) => urls.push(url)
              _ => ()
            }
          }
          Some(urls)
        }
        _ => None
      }
    _ => None
  }
}

///|
fn oauth_authorization_server_metadata_url(issuer : String) -> String {
  let normalized = match issuer.strip_suffix("/") {
    Some(value) => value.to_owned()
    None => issuer
  }
  let well_known = "/.well-known/oauth-authorization-server"
  match normalized.split_once("://") {
    Some((scheme, rest)) =>
      match rest.find("/") {
        Some(path_start) => {
          let host = rest.view(end_offset=path_start).to_owned()
          let path = rest.view(start_offset=path_start).to_owned()
          scheme.to_owned() + "://" + host + well_known + path
        }
        None => normalized + well_known
      }
    None => normalized + well_known
  }
}
