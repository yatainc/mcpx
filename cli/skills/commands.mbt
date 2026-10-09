///|
pub(all) enum Operation {
  List
  Get(String)
  Verify(String)
  Read(String)
} derive(Debug)

///|
pub extend Operation with Debug::{to_repr}

///|
pub(all) struct Command {
  target : String
  operation : Operation
  json_output : Bool
} derive(Debug)

///|
pub extend Command with Debug::{to_repr}

///|
pub(all) suberror RetrievalError {
  RetrievalError(String)
}
