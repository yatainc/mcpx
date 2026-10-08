///|
pub struct AuthHint {
  server_name : String
  status_code : Int
  summary : String
  suggested_commands : Array[String]
  config_hint : String?
  opens_browser : Bool
} derive(Debug)

///|
pub extend AuthHint with Debug::{to_repr}

///|
pub fn auth_required_hint(
  server_name~ : String,
  status_code~ : Int,
  token_env_var? : String? = None,
) -> AuthHint? {
  match status_code {
    401 =>
      Some(
        auth_hint(
          server_name, status_code, "Unauthorized", "Authentication is required.",
          token_env_var,
        ),
      )
    403 =>
      Some(
        auth_hint(
          server_name, status_code, "Forbidden", "Token scopes or authorization may be insufficient.",
          token_env_var,
        ),
      )
    _ => None
  }
}

///|
fn auth_hint(
  server_name : String,
  status_code : Int,
  reason : String,
  detail : String,
  token_env_var : String?,
) -> AuthHint {
  {
    server_name,
    status_code,
    summary: server_name +
    " returned " +
    status_code.to_string() +
    " " +
    reason +
    ". " +
    detail,
    suggested_commands: [
      "mcpx auth " + server_name,
      "mcpx auth " + server_name + " --no-browser --json",
    ],
    config_hint: token_env_var.map(auth_header_config_hint),
    opens_browser: false,
  }
}

///|
fn auth_header_config_hint(env_var : String) -> String {
  let out = StringBuilder(size_hint=env_var.length() + 36)
  out.write_string("headers.Authorization = \"Bearer ")
  out.write_char('$')
  out.write_char('{')
  out.write_string(env_var)
  out.write_char('}')
  out.write_char('\"')
  out.to_string()
}
