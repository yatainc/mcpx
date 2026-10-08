///|
pub(all) struct CallCommand {
  server : String
  url : String?
  tool : String
  arguments_json : String?
} derive(Debug)

///|
pub extend CallCommand with Debug::{to_repr}

///|
pub(all) struct InfoCommand {
  server : String?
  url : String?
  tool : String?
} derive(Debug)

///|
pub extend InfoCommand with Debug::{to_repr}
