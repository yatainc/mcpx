///|
#derive(Debug)
pub(all) enum Operation {
  List
  Get(String)
  Verify(String)
  Read(String)
}

///|
pub extend Operation with Debug::{to_repr}

///|
#derive(Debug)
pub(all) struct Command {
  target : String
  operation : Operation
  json_output : Bool
}

///|
pub extend Command with Debug::{to_repr}

///|
pub(all) suberror RetrievalError {
  RetrievalError(String)
}
