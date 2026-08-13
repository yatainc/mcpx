///|
priv enum HttpProtocolLifecycle {
  Modern(@protocol.McpProtocolVersion)
  InitializeEra(@protocol.McpProtocolVersion)
}

///|
priv enum DiscoverHttpOutcome {
  LegacySignal
  Discover(@protocol.McpDiscoverInfo)
}

///|
async fn negotiate(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
) -> HttpProtocolLifecycle raise McpHttpClientError {
  // An explicit stateful preference selects the initialize lifecycle directly.
  // Only auto mode may downgrade from discovery to initialize-era MCP.
  if endpoint.mode == @config.McpConnectionMode::Stateful {
    return HttpProtocolLifecycle::InitializeEra(
      @protocol.McpProtocolVersion::V2025_11_25,
    )
  }
  let requested = @protocol.McpProtocolVersion::V2026_07_28
  let response = send_discover(fetch, endpoint, requested)
  let outcome = parse_discover_http_response(response, expected_id=1) catch {
    McpHttpClientError::UnsupportedProtocolVersion(supported) => {
      let parsed = supported.map(@protocol.parse_mcp_protocol_version)
      match select_compatible_version(endpoint.mode, parsed) {
        Some(version) if version == requested => {
          let retry = send_discover(fetch, endpoint, version)
          return negotiation_from_discover(
            endpoint.mode,
            decode_discover_http_response(retry),
          )
        }
        Some(version) =>
          return match @protocol.mcp_protocol_family(version) {
            @protocol.McpProtocolFamily::InitializeEra =>
              HttpProtocolLifecycle::InitializeEra(version)
            @protocol.McpProtocolFamily::StatelessCore => {
              let retry = send_discover(fetch, endpoint, version)
              negotiation_from_discover(
                endpoint.mode,
                decode_discover_http_response(retry),
              )
            }
            @protocol.McpProtocolFamily::Unsupported =>
              raise McpHttpClientError::UnsupportedProtocolVersion(supported)
          }
        None => raise_incompatible_or_unsupported(endpoint.mode, parsed)
      }
    }
    error => raise error
  }
  match outcome {
    DiscoverHttpOutcome::LegacySignal => {
      if endpoint.mode == @config.McpConnectionMode::Auto {
        HttpProtocolLifecycle::InitializeEra(
          @protocol.McpProtocolVersion::V2025_11_25,
        )
      } else {
        raise McpHttpClientError::ModeProtocolIncompatible(
          "stateless", "initialize-era",
        )
      }
    }
    DiscoverHttpOutcome::Discover(discover) =>
      negotiation_from_discover(endpoint.mode, discover)
  }
}

///|
fn negotiation_from_discover(
  mode : @config.McpConnectionMode,
  discover : @protocol.McpDiscoverInfo,
) -> HttpProtocolLifecycle raise McpHttpClientError {
  let selected = match
    select_compatible_version(mode, discover.protocol_versions) {
    Some(value) => value
    None => raise_incompatible_or_unsupported(mode, discover.protocol_versions)
  }
  match @protocol.mcp_protocol_family(selected) {
    @protocol.McpProtocolFamily::StatelessCore => {
      if mode == @config.McpConnectionMode::Stateful {
        raise McpHttpClientError::ModeProtocolIncompatible(
          "stateful", "2026-07-28",
        )
      }
      HttpProtocolLifecycle::Modern(selected)
    }
    @protocol.McpProtocolFamily::InitializeEra =>
      HttpProtocolLifecycle::InitializeEra(selected)
    @protocol.McpProtocolFamily::Unsupported =>
      raise McpHttpClientError::UnsupportedProtocolVersion([
        @protocol.mcp_protocol_version_to_string(selected),
      ])
  }
}

///|
fn select_compatible_version(
  mode : @config.McpConnectionMode,
  advertised : Array[@protocol.McpProtocolVersion],
) -> @protocol.McpProtocolVersion? {
  match mode {
    @config.McpConnectionMode::Auto =>
      @protocol.newest_compatible_mcp_protocol_version(
        advertised,
        allow_stateless_core=true,
      )
    @config.McpConnectionMode::Stateful =>
      @protocol.newest_compatible_mcp_protocol_version(
        advertised,
        allow_stateless_core=false,
      )
    @config.McpConnectionMode::Stateless =>
      if advertised.contains(@protocol.McpProtocolVersion::V2026_07_28) {
        Some(@protocol.McpProtocolVersion::V2026_07_28)
      } else {
        None
      }
  }
}

///|
fn[T] raise_incompatible_or_unsupported(
  mode : @config.McpConnectionMode,
  advertised : Array[@protocol.McpProtocolVersion],
) -> T raise McpHttpClientError {
  let has_modern = advertised.any(version => {
    @protocol.mcp_protocol_family(version) ==
    @protocol.McpProtocolFamily::StatelessCore
  })
  let has_initialize = advertised.any(version => {
    @protocol.mcp_protocol_family(version) ==
    @protocol.McpProtocolFamily::InitializeEra
  })
  match mode {
    @config.McpConnectionMode::Stateful if has_modern =>
      raise McpHttpClientError::ModeProtocolIncompatible(
        "stateful", "2026-07-28",
      )
    @config.McpConnectionMode::Stateless if has_initialize =>
      raise McpHttpClientError::ModeProtocolIncompatible(
        "stateless", "initialize-era",
      )
    _ =>
      raise McpHttpClientError::UnsupportedProtocolVersion(
        advertised.map(@protocol.mcp_protocol_version_to_string),
      )
  }
}

///|
async fn send_discover(
  fetch : async (HttpRequest) -> HttpResponse,
  endpoint : Endpoint,
  version : @protocol.McpProtocolVersion,
) -> HttpResponse raise McpHttpClientError {
  let context = @protocol.mcp_request_context(
    protocol=version,
    client_name=@protocol.MCPX_CLIENT_NAME,
    client_version=@protocol.MCPX_CLIENT_VERSION,
  )
  post_json(
    fetch,
    endpoint,
    build_modern_headers(endpoint.headers, version, "server/discover", None),
    @protocol.mcp_discover_request(id=1, context),
  )
}

///|
fn decode_discover_http_response(
  response : HttpResponse,
) -> @protocol.McpDiscoverInfo raise McpHttpClientError {
  let json = response_json(response)
  match @protocol.decode_mcp_discover_response(json, expected_id=1) {
    Ok(value) => value
    Err(error) => raise protocol_error_to_http(error)
  }
}

///|
fn parse_discover_http_response(
  response : HttpResponse,
  expected_id~ : Int,
) -> DiscoverHttpOutcome raise McpHttpClientError {
  let permits_legacy_signal = response.status_code == 400 ||
    response.status_code == 404 ||
    response.status_code == 405
  if permits_legacy_signal {
    if response.body.trim().is_empty() {
      return DiscoverHttpOutcome::LegacySignal
    }
    let json = @json.parse(response.body) catch {
      _ => return DiscoverHttpOutcome::LegacySignal
    }
    try @protocol.decode_mcp_result(json, expected_id~) catch {
      @protocol.McpProtocolError::InvalidResponse(_) =>
        return DiscoverHttpOutcome::LegacySignal
      error => raise protocol_error_to_http(error)
    } noraise {
      _ => raise McpHttpClientError::HttpStatus(response.status_code)
    }
  }
  DiscoverHttpOutcome::Discover(decode_discover_http_response(response))
}
