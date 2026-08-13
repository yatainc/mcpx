///|
suberror OAuthPkceError {
  RandomBytesFailed
} derive(Debug)

///|
#borrow(buf)
extern "C" fn random_bytes_ffi(buf : FixedArray[Byte], len : Int) -> Int = "mcpx_oauth_random_bytes"

///|
pub fn pkce_s256_challenge(verifier : String) -> String {
  let bytes = @encoding.encode(UTF8, verifier)
  let digest = @crypto.sha256(bytes)
  base64url(Bytes::from_iter(digest.iter()))
}

///|
pub fn random_urlsafe_token(byte_length : Int) -> String raise OAuthPkceError {
  let bytes = random_bytes(byte_length)
  base64url(bytes)
}

///|
pub fn base64url(data : BytesView) -> String {
  @base64.encode(data, padding=false)
  .replace_all(old="+", new="-")
  .replace_all(old="/", new="_")
}

///|
fn random_bytes(byte_length : Int) -> Bytes raise OAuthPkceError {
  let bytes = FixedArray::make(byte_length, b'\x00')
  guard random_bytes_ffi(bytes, byte_length) == 0 else {
    raise RandomBytesFailed
  }
  bytes.unsafe_reinterpret_as_bytes()
}
