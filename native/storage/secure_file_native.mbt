///|
suberror SecureFileError {
  SecureWriteFailed
  SecureStatFailed
} derive(Debug)

///|
#borrow(path, contents)
extern "C" fn secure_write_private_atomic_ffi(
  path : String,
  contents : String,
) -> Int = "mcpx_secure_write_private_atomic"

///|
#borrow(path)
extern "C" fn secure_file_mode_ffi(path : String) -> Int = "mcpx_secure_file_mode"

///|
pub fn secure_write_private_atomic(
  path : String,
  contents : String,
) -> Unit raise SecureFileError {
  guard secure_write_private_atomic_ffi(path, contents) == 0 else {
    raise SecureWriteFailed
  }
}

///|
pub fn secure_file_mode(path : String) -> Int raise SecureFileError {
  let mode = secure_file_mode_ffi(path)
  guard mode >= 0 else { raise SecureStatFailed }
  mode
}
