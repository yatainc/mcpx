///|
pub(all) struct CallCommand {
  server : String
  url : String?
  tool : String
  arguments_json : String?
} derive(Debug)

///|
pub(all) struct InfoCommand {
  server : String?
  url : String?
  tool : String?
} derive(Debug)
