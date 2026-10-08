///|
test "oauth pkce: S256 challenge matches RFC 7636 vector" {
  inspect(
    @oauth.pkce_s256_challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
    content="E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
  )
}

///|
test "oauth pkce: base64url has no padding" {
  inspect(@oauth.base64url(b"foo"), content="Zm9v")
  inspect(@oauth.base64url(b"light w"), content="bGlnaHQgdw")
}
