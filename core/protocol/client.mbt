///|
pub(all) enum McpClientRequestKind {
  Initialize
  InitializedNotification
  ToolsList
  ToolsCall(String)
} derive(Debug)

///|
pub struct McpClientRequest {
  kind : McpClientRequestKind
  id : Int?
  message : Json
} derive(Debug)

///|
pub struct McpClient {
  client_name : String
  client_version : String
  protocol_version : String
  session : McpSession
} derive(Debug)

///|
pub fn mcp_client(
  client_name~ : String,
  client_version~ : String,
  protocol_version? : String = MCP_PROTOCOL_VERSION,
) -> McpClient {
  { client_name, client_version, protocol_version, session: mcp_session() }
}

///|
pub fn McpClient::is_initialized(self : McpClient) -> Bool {
  self.session.is_initialized()
}

///|
pub fn McpClient::initialize_request(self : McpClient) -> McpClientRequest {
  let id = self.session.next_request_id()
  {
    kind: McpClientRequestKind::Initialize,
    id: Some(id),
    message: mcp_initialize_request(
      id~,
      client_name=self.client_name,
      client_version=self.client_version,
      protocol_version=self.protocol_version,
    ),
  }
}

///|
pub fn McpClient::initialized_notification(
  self : McpClient,
) -> McpClientRequest {
  ignore(self)
  {
    kind: McpClientRequestKind::InitializedNotification,
    id: None,
    message: mcp_initialized_notification(),
  }
}

///|
pub fn McpClient::tools_list_request(self : McpClient) -> McpClientRequest {
  let id = self.session.next_request_id()
  {
    kind: McpClientRequestKind::ToolsList,
    id: Some(id),
    message: mcp_tools_list_request_legacy(id~),
  }
}

///|
pub fn McpClient::tool_call_request(
  self : McpClient,
  name~ : String,
  arguments~ : Json,
) -> McpClientRequest {
  let id = self.session.next_request_id()
  {
    kind: McpClientRequestKind::ToolsCall(name),
    id: Some(id),
    message: mcp_tool_call_request_legacy(id~, name~, arguments~),
  }
}

///|
pub fn McpClient::accept_initialize_response(
  self : McpClient,
  request : McpClientRequest,
  response : Json,
) -> McpInitializeInfo raise McpProtocolError {
  let id = request.expected_id()
  let info = match decode_mcp_initialize_response(response, expected_id=id) {
    Ok(value) => value
    Err(error) => raise error
  }
  self.session.mark_initialized(info)
  info
}

///|
pub fn McpClient::accept_tools_list_response(
  self : McpClient,
  request : McpClientRequest,
  response : Json,
) -> Array[McpToolInfo] raise McpProtocolError {
  ignore(self)
  let id = request.expected_id()
  match decode_mcp_tool_list_response(response, expected_id=id) {
    Ok(value) => value
    Err(error) => raise error
  }
}

///|
pub fn McpClient::accept_tool_call_response(
  self : McpClient,
  request : McpClientRequest,
  response : Json,
) -> Json raise McpProtocolError {
  ignore(self)
  decode_mcp_result(response, expected_id=request.expected_id())
}

///|
pub fn McpClientRequest::expected_id(
  self : McpClientRequest,
) -> Int raise McpProtocolError {
  match self.id {
    Some(id) => id
    None =>
      raise McpProtocolError::InvalidResponse("request has no response id")
  }
}
