///|
fn resolve_auth_env(
  auth : ServerAuthConfig,
  env : Map[String, String],
) -> Result[ServerAuthConfig, EnvTemplateError] {
  let client_id = match resolve_optional_template(auth.client_id, env) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let client_secret = match resolve_optional_template(auth.client_secret, env) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let metadata_url = match resolve_optional_template(auth.metadata_url, env) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({
    kind: auth.kind,
    client_id,
    client_secret,
    metadata_url,
    scopes: auth.scopes,
  })
}

///|
fn resolve_optional_template(
  value : String?,
  env : Map[String, String],
) -> Result[String?, EnvTemplateError] {
  match value {
    None => Ok(None)
    Some(template) => {
      let resolved = resolve_env_template(template, env) catch {
        error => return Err(error)
      }
      Ok(Some(resolved))
    }
  }
}

///|
fn resolve_string_array(
  values : Array[String],
  env : Map[String, String],
) -> Result[Array[String], EnvTemplateError] {
  let resolved = []
  for value in values {
    let next = resolve_env_template(value, env) catch {
      error => return Err(error)
    }
    resolved.push(next)
  }
  Ok(resolved)
}

///|
fn resolve_string_map(
  values : Map[String, String],
  env : Map[String, String],
) -> Result[Map[String, String], EnvTemplateError] {
  let resolved = Map([], capacity=values.length())
  for key, value in values {
    let next = resolve_env_template(value, env) catch {
      error => return Err(error)
    }
    resolved[key] = next
  }
  Ok(resolved)
}
