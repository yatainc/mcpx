///|
#derive(Debug)
pub enum HostAction {
  ReadTextFile(HostReadTextFile)
  WriteTextFile(HostWriteTextFile)
  OpenBrowser(HostOpenBrowser)
  HttpRequest(HostHttpRequest)
}

///|
pub extend HostAction with Debug::{to_repr}

///|
#derive(Debug)
pub struct HostReadTextFile {
  path : String
}

///|
pub extend HostReadTextFile with Debug::{to_repr}

///|
#derive(Debug)
pub struct HostWriteTextFile {
  path : String
  contents : String
  mode : Int32
  atomic_write : Bool
  create_parent_dirs : Bool
}

///|
pub extend HostWriteTextFile with Debug::{to_repr}

///|
#derive(Debug)
pub struct HostOpenBrowser {
  url : String
}

///|
pub extend HostOpenBrowser with Debug::{to_repr}

///|
#derive(Debug)
pub struct HostHttpRequest {
  http_method : String
  url : String
  headers : Map[String, String]
  body : String?
}

///|
pub extend HostHttpRequest with Debug::{to_repr}

///|
pub fn host_read_text_file(path~ : String) -> HostAction {
  ReadTextFile({ path, })
}

///|
pub fn host_write_private_text_file(
  path~ : String,
  contents~ : String,
) -> HostAction {
  WriteTextFile({
    path,
    contents,
    mode: 384,
    atomic_write: true,
    create_parent_dirs: true,
  })
}

///|
pub fn host_open_browser(url~ : String) -> HostAction {
  OpenBrowser({ url, })
}

///|
pub fn host_http_request(
  http_method~ : String,
  url~ : String,
  headers~ : Map[String, String] = Map([]),
  body~ : String? = None,
) -> HostAction {
  HttpRequest({ http_method, url, headers, body, })
}

///|
pub extend HostAction with ToJson::{to_json}

///|
pub impl ToJson for HostAction with fn to_json(self) {
  match self {
    ReadTextFile(action) => action.to_json()
    WriteTextFile(action) => action.to_json()
    OpenBrowser(action) => action.to_json()
    HttpRequest(action) => action.to_json()
  }
}

///|
pub extend HostReadTextFile with ToJson::{to_json}

///|
pub impl ToJson for HostReadTextFile with fn to_json(self) {
  let obj = Map([])
  obj["kind"] = Json::string("read_text_file")
  obj["path"] = Json::string(self.path)
  Json::object(obj)
}

///|
pub extend HostWriteTextFile with ToJson::{to_json}

///|
pub impl ToJson for HostWriteTextFile with fn to_json(self) {
  let obj = Map([])
  obj["kind"] = Json::string("write_text_file")
  obj["path"] = Json::string(self.path)
  obj["contents"] = Json::string(self.contents)
  obj["mode"] = json_int(self.mode)
  obj["atomic"] = Json::boolean(self.atomic_write)
  obj["createParentDirs"] = Json::boolean(self.create_parent_dirs)
  Json::object(obj)
}

///|
pub extend HostOpenBrowser with ToJson::{to_json}

///|
pub impl ToJson for HostOpenBrowser with fn to_json(self) {
  let obj = Map([])
  obj["kind"] = Json::string("open_browser")
  obj["url"] = Json::string(self.url)
  Json::object(obj)
}

///|
fn json_int(value : Int32) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
pub extend HostHttpRequest with ToJson::{to_json}

///|
pub impl ToJson for HostHttpRequest with fn to_json(self) {
  let obj = Map([])
  obj["kind"] = Json::string("http_request")
  obj["method"] = Json::string(self.http_method)
  obj["url"] = Json::string(self.url)
  obj["headers"] = string_map_to_json(self.headers)
  match self.body {
    Some(value) => obj["body"] = Json::string(value)
    None => ()
  }
  Json::object(obj)
}

///|
fn string_map_to_json(map : Map[String, String]) -> Json {
  let obj = Map([], capacity=map.length())
  for key, value in map {
    obj[key] = Json::string(value)
  }
  Json::object(obj)
}
