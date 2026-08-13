///|
pub struct McpRequestContext {
  protocol : McpProtocolVersion
  client_name : String
  client_version : String
  client_capabilities : Map[String, Json]
}

///|
pub fn mcp_request_context(
  protocol~ : McpProtocolVersion,
  client_name~ : String,
  client_version~ : String,
  client_capabilities? : Map[String, Json] = Map([]),
) -> McpRequestContext {
  { protocol, client_name, client_version, client_capabilities }
}

///|
pub fn mcp_request_meta(context : McpRequestContext) -> Json {
  let meta = Map([])
  meta["io.modelcontextprotocol/protocolVersion"] = Json::string(
    mcp_protocol_version_to_string(context.protocol),
  )
  meta["io.modelcontextprotocol/clientInfo"] = Json::object({
    "name": Json::string(context.client_name),
    "version": Json::string(context.client_version),
  })
  meta["io.modelcontextprotocol/clientCapabilities"] = Json::object(
    context.client_capabilities.copy(),
  )
  Json::object(meta)
}

///|
pub fn with_mcp_request_meta(
  params : Map[String, Json],
  context : McpRequestContext,
) -> Json {
  let result = params.copy()
  result["_meta"] = mcp_request_meta(context)
  Json::object(result)
}
