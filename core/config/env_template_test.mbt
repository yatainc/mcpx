///|
test "env template: resolves ${VAR} from provided env" {
  inspect(
    @config.resolve_env_template("Bearer ${TOKEN}", { "TOKEN": "abc" }),
    content="Bearer abc",
  )
}

///|
test "env template: missing var raises in strict mode" {
  let result : Result[String, @config.EnvTemplateError] = try
    @config.resolve_env_template("Bearer ${TOKEN}", Map([])) |> Ok
  catch {
    e => Err(e)
  }
  @debug.debug_inspect(result, content="Err(MissingEnvVar(\"TOKEN\"))")
}

///|
test "env template: non-strict missing var becomes empty" {
  inspect(
    @config.resolve_env_template("Bearer ${TOKEN}", Map([]), strict=false),
    content="Bearer ",
  )
}

///|
test "env template: rejects fallback syntax because only ${VAR} is supported" {
  let result : Result[String, @config.EnvTemplateError] = try
    @config.resolve_env_template("${TOKEN:-fallback}", { "TOKEN": "abc" }) |> Ok
  catch {
    e => Err(e)
  }
  @debug.debug_inspect(
    result,
    content="Err(InvalidEnvVarSyntax(\"${TOKEN:-fallback}\"))",
  )
}

///|
test "env template: rejects empty placeholder" {
  let result : Result[String, @config.EnvTemplateError] = try
    @config.resolve_env_template("${}", Map([])) |> Ok
  catch {
    e => Err(e)
  }
  @debug.debug_inspect(result, content="Err(InvalidEnvVarSyntax(\"${}\"))")
}
