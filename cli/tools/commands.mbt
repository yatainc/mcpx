///|
#derive(Debug)
pub(all) struct CallCommand {
  server : String
  url : String?
  tool : String
  arguments_json : String?
}

///|
pub extend CallCommand with Debug::{to_repr}

///|
#derive(Debug)
pub(all) struct InfoCommand {
  server : String?
  url : String?
  tool : String?
}

///|
pub extend InfoCommand with Debug::{to_repr}
