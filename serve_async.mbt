///|
fn request_method_to_string(meth : @http.RequestMethod) -> String {
  match meth {
    Get => "GET"
    Head => "HEAD"
    Post => "POST"
    Put => "PUT"
    Delete => "DELETE"
    Connect => "CONNECT"
    Options => "OPTIONS"
    Trace => "TRACE"
    Patch => "PATCH"
  }
}

///|
test "request_method_to_string converts all HTTP methods" {
  inspect(request_method_to_string(Get), content="GET")
  inspect(request_method_to_string(Head), content="HEAD")
  inspect(request_method_to_string(Post), content="POST")
  inspect(request_method_to_string(Put), content="PUT")
  inspect(request_method_to_string(Delete), content="DELETE")
  inspect(request_method_to_string(Connect), content="CONNECT")
  inspect(request_method_to_string(Options), content="OPTIONS")
  inspect(request_method_to_string(Trace), content="TRACE")
  inspect(request_method_to_string(Patch), content="PATCH")
}

/// Copies request headers from the async runtime.
/// Uses Map::from_iter for efficient bulk construction instead of
/// per-key insertion.

///|
fn copy_async_headers(headers : Map[String, String]) -> Map[String, String] {
  Map::from_iter(headers.iter())
}

///|
let cached_date_second : Ref[Int64] = Ref::new(0L)

///|
let cached_date_string : Ref[String] = Ref::new("")

///|
fn current_http_date() -> String {
  let now = @async.now() / 1000L
  if now != cached_date_second.val {
    cached_date_second.val = now
    cached_date_string.val = @httputil.format_http_date(now)
  }
  cached_date_string.val
}

///|
let ws_serve_runtime_counter : Ref[Int] = Ref::new(0)

///|
fn next_ws_serve_runtime_id(app : Mocket) -> String {
  ws_serve_runtime_counter.val += 1
  "\{app.ws_runtime_id}/serve-\{ws_serve_runtime_counter.val}"
}

///|
fn append_cookie_headers(
  headers : Map[String, String],
  cookies : Map[String, @cookie.CookieItem],
) -> Unit {
  if cookies.is_empty() {
    return
  }
  let cookie_lines = cookies
    .values()
    .map(cookie => cookie.to_string())
    .to_array()
  match cookie_lines {
    [] => ()
    [cookie] => headers.set("Set-Cookie", cookie)
    _ => headers.set("Set-Cookie", cookie_lines.join("\r\nSet-Cookie: "))
  }
}

///|
test "append_cookie_headers with empty cookies does nothing" {
  let headers : Map[String, String] = {}
  let cookies : Map[String, @cookie.CookieItem] = {}
  append_cookie_headers(headers, cookies)
  inspect(headers.contains("Set-Cookie"), content="false")
}

///|
test "append_cookie_headers with single cookie sets header" {
  let headers : Map[String, String] = {}
  let cookies : Map[String, @cookie.CookieItem] = {}
  cookies.set("session", {
    name: "session",
    value: "abc123",
    max_age: None,
    path: None,
    domain: None,
    secure: None,
    http_only: None,
    same_site: None,
  })
  append_cookie_headers(headers, cookies)
  inspect(
    headers.get("Set-Cookie"),
    content=(
      #|Some("session=abc123")
    ),
  )
}

///|
test "append_cookie_headers with multiple cookies joins with CRLF Set-Cookie" {
  let headers : Map[String, String] = {}
  let cookies : Map[String, @cookie.CookieItem] = {}
  cookies.set("a", {
    name: "a",
    value: "1",
    max_age: None,
    path: None,
    domain: None,
    secure: None,
    http_only: None,
    same_site: None,
  })
  cookies.set("b", {
    name: "b",
    value: "2",
    max_age: None,
    path: None,
    domain: None,
    secure: None,
    http_only: None,
    same_site: None,
  })
  append_cookie_headers(headers, cookies)
  inspect(
    headers.get("Set-Cookie"),
    content=(
      #|Some("a=1\r\nSet-Cookie: b=2")
    ),
  )
}

///|
fn header_contains_token_case_insensitive(
  headers : Map[String, String],
  header_name : String,
  token_name : String,
) -> Bool {
  let normalized_token_name = token_name.to_lower()
  match @httputil.get_header_case_insensitive(headers, header_name) {
    Some(value) => {
      for token in value.split(",") {
        if token.trim().to_lower() == normalized_token_name {
          return true
        }
      }
      false
    }
    None => false
  }
}

///|
test "header_contains_token_case_insensitive finds token in comma-separated list" {
  let headers : Map[String, String] = { "Connection": "keep-alive, Upgrade" }
  inspect(
    header_contains_token_case_insensitive(headers, "Connection", "upgrade"),
    content="true",
  )
}

///|
test "header_contains_token_case_insensitive returns false when token not found" {
  let headers : Map[String, String] = { "Connection": "keep-alive" }
  inspect(
    header_contains_token_case_insensitive(headers, "Connection", "upgrade"),
    content="false",
  )
}

///|
test "header_contains_token_case_insensitive is case insensitive on header name" {
  let headers : Map[String, String] = { "CONNECTION": "Upgrade" }
  inspect(
    header_contains_token_case_insensitive(headers, "connection", "upgrade"),
    content="true",
  )
}

///|
test "header_contains_token_case_insensitive returns false for missing header" {
  let headers : Map[String, String] = {}
  inspect(
    header_contains_token_case_insensitive(headers, "Connection", "upgrade"),
    content="false",
  )
}

///|
fn @http.Request::is_websocket_upgrade_request(request : Self) -> Bool {
  let has_connection_upgrade = header_contains_token_case_insensitive(
    request.headers,
    "connection",
    "upgrade",
  )
  let has_websocket_upgrade = match
    @httputil.get_header_case_insensitive(request.headers, "upgrade") {
    Some(value) => value.trim().to_lower() == "websocket"
    None => false
  }
  has_connection_upgrade && has_websocket_upgrade
}

///|
test "is_websocket_upgrade_request returns true with both headers" {
  let request : @http.Request = {
    meth: Get,
    path: "/",
    headers: { "Connection": "upgrade", "Upgrade": "websocket" },
  }
  inspect(request.is_websocket_upgrade_request(), content="true")
}

///|
test "is_websocket_upgrade_request returns false without Connection header" {
  let request : @http.Request = {
    meth: Get,
    path: "/",
    headers: { "Upgrade": "websocket" },
  }
  inspect(request.is_websocket_upgrade_request(), content="false")
}

///|
test "is_websocket_upgrade_request returns false without Upgrade header" {
  let request : @http.Request = {
    meth: Get,
    path: "/",
    headers: { "Connection": "upgrade" },
  }
  inspect(request.is_websocket_upgrade_request(), content="false")
}

///|
test "is_websocket_upgrade_request returns false with empty headers" {
  let request : @http.Request = { meth: Get, path: "/", headers: {} }
  inspect(request.is_websocket_upgrade_request(), content="false")
}

///|
fn looks_like_websocket_handshake_request(request : @http.Request) -> Bool {
  let websocket_upgrade_header = match
    @httputil.get_header_case_insensitive(request.headers, "upgrade") {
    Some(value) => value.trim().to_lower() == "websocket"
    None => false
  }
  for pair in request.headers {
    let (key, _) = pair
    if key.to_lower().has_prefix("sec-websocket-") {
      return true
    }
  }
  request.is_websocket_upgrade_request() || websocket_upgrade_header
}

///|
priv enum HttpRouteLookup {
  Found(HttpHandler, Map[String, StringView])
  MethodNotAllowed(String)
  Options(String)
  NotFound
}

///|
fn allow_header_value(methods : Array[String]) -> String {
  methods.join(", ")
}

///|
test "allow_header_value joins methods with comma and space" {
  inspect(allow_header_value(["GET", "POST", "PUT"]), content="GET, POST, PUT")
}

///|
test "allow_header_value with single method" {
  inspect(allow_header_value(["GET"]), content="GET")
}

///|
test "allow_header_value with empty array" {
  inspect(allow_header_value([]), content="")
}

///|
fn method_not_allowed_handler(allow : String) -> HttpHandler {
  HttpHandler(event => {
    event.res.headers.set("Allow", allow)
    HttpResponse(status_code=MethodNotAllowed).body("Method Not Allowed")
  })
}

///|
fn options_handler(allow : String) -> HttpHandler {
  HttpHandler(event => {
    event.res.headers.set("Allow", allow)
    HttpResponse(status_code=NoContent)
  })
}

///|
async fn send_raw_response_async(
  conn : @http.ServerConnection,
  response : HttpResponse,
  headers : Map[String, String],
  include_body : Bool,
) -> Unit {
  if !@httputil.has_header_case_insensitive(headers, "Date") {
    headers.set("Date", current_http_date())
  }
  if !@httputil.has_header_case_insensitive(headers, "Content-Length") {
    headers.set("Content-Length", response.raw_body.length().to_string())
  }
  if !@httputil.has_header_case_insensitive(headers, "Connection") {
    headers.set("Connection", "close")
  }
  let raw_response = @buffer.new()
  raw_response.write_string_utf8("HTTP/1.1 ")
  raw_response.write_string_utf8(response.status_code.to_int().to_string())
  raw_response.write_string_utf8(" ")
  raw_response.write_string_utf8(response.status_code.to_string())
  raw_response.write_string_utf8("\r\n")
  for pair in headers.to_array() {
    let (key, value) = pair
    raw_response.write_string_utf8(key)
    raw_response.write_string_utf8(": ")
    raw_response.write_string_utf8(value)
    raw_response.write_string_utf8("\r\n")
  }
  raw_response.write_string_utf8("\r\n")
  if include_body && !response.raw_body.is_empty() {
    raw_response.write_bytes(response.raw_body)
  }
  conn.enter_passthrough_mode()
  conn.write(raw_response.contents())
  conn.flush()
  conn.close()
}

///|
fn Mocket::lookup_http_route(
  self : Mocket,
  http_method : String,
  request_path : String,
) -> HttpRouteLookup {
  match self.find_route(http_method, request_path) {
    Some((handler, params)) => return Found(handler, params)
    None => ()
  }
  if http_method == "HEAD" {
    match self.find_route_for_method("GET", request_path) {
      Some((handler, params)) => return Found(handler, params)
      None => ()
    }
  }
  let allow = self.allowed_methods(request_path, http_method == "OPTIONS")
  if allow.is_empty() {
    NotFound
  } else if http_method == "OPTIONS" {
    Options(allow_header_value(allow))
  } else {
    MethodNotAllowed(allow_header_value(allow))
  }
}

///|
/// Applies a responder to a response and serializes pending cookies into
/// `Set-Cookie` headers. Shared by the live serving path
/// (`send_response_async`) and synthetic dispatch (`Mocket::dispatch`) so the
/// two stay aligned: any bug in body materialization or cookie serialization
/// would otherwise have to be fixed twice (see commits bb22108, eb6f24b).
fn finalize_response_body(
  response : HttpResponse,
  responder : &Responder,
) -> Unit {
  responder.options(response)
  // Fast path: use output_bytes to avoid buffer allocation when possible
  match responder.output_bytes() {
    Some(bytes) => response.raw_body = bytes
    None => {
      let buffer = @buffer.new()
      responder.output(buffer)
      response.raw_body = buffer.to_bytes()
    }
  }
  append_cookie_headers(response.headers, response.cookies)
}

///|
async fn send_response_async(
  request : @http.Request,
  conn : @http.ServerConnection,
  response : HttpResponse,
  responder : &Responder,
) -> Unit {
  finalize_response_body(response, responder)
  let headers = response.headers
  if !@httputil.has_header_case_insensitive(headers, "Date") {
    headers.set("Date", current_http_date())
  }
  if request.meth == Head {
    send_raw_response_async(conn, response, headers, false)
    return
  }
  if @httputil.has_header_case_insensitive(headers, "Content-Encoding") {
    send_raw_response_async(conn, response, headers, true)
    return
  }
  conn.send_response(
    response.status_code.to_int(),
    response.status_code.to_string(),
    extra_headers=headers,
  )
  if !response.raw_body.is_empty() {
    conn.write(response.raw_body)
  }
  conn.end_response()
}

///|
async fn send_response_and_close_async(
  request : @http.Request,
  conn : @http.ServerConnection,
  response : HttpResponse,
) -> Unit {
  let headers = response.headers
  append_cookie_headers(headers, response.cookies)
  if !@httputil.has_header_case_insensitive(headers, "Date") {
    headers.set("Date", current_http_date())
  }
  if !@httputil.has_header_case_insensitive(headers, "Content-Length") {
    headers.set("Content-Length", response.raw_body.length().to_string())
  }
  headers.set("Connection", "close")
  if request.meth == Head {
    send_raw_response_async(conn, response, headers, false)
    return
  }
  conn.send_response(
    response.status_code.to_int(),
    response.status_code.to_string(),
    extra_headers=headers,
  )
  if !response.raw_body.is_empty() {
    conn.write(response.raw_body)
  }
  conn.end_response()
  conn.close()
}

///|
async fn send_request_entity_too_large_async(
  request : @http.Request,
  conn : @http.ServerConnection,
) -> Unit {
  let response = HttpResponse(status_code=RequestEntityTooLarge).body(
    "Request Entity Too Large",
  )
  response.headers.set("Content-Type", "text/plain; charset=utf-8")
  send_response_and_close_async(request, conn, response)
}

///|
async fn send_request_timeout_async(
  request : @http.Request,
  conn : @http.ServerConnection,
) -> Unit {
  let response = HttpResponse(status_code=RequestTimeout).body(
    "Request Timeout",
  )
  response.headers.set("Content-Type", "text/plain; charset=utf-8")
  send_response_and_close_async(request, conn, response)
}

///|
async fn send_not_found_async(
  request : @http.Request,
  conn : @http.ServerConnection,
) -> Unit {
  let response = HttpResponse(status_code=NotFound).body("Not Found")
  response.headers.set("Content-Type", "text/plain; charset=utf-8")
  send_response_and_close_async(request, conn, response)
}

///|
async fn send_gateway_timeout_async(
  request : @http.Request,
  conn : @http.ServerConnection,
) -> Unit {
  let response = HttpResponse(status_code=GatewayTimeout).body(
    "Gateway Timeout",
  )
  response.headers.set("Content-Type", "text/plain; charset=utf-8")
  send_response_and_close_async(request, conn, response)
}

///|
fn request_content_length(request : @http.Request) -> Int? {
  match
    @httputil.get_header_case_insensitive(request.headers, "content-length") {
    Some(value) => Some(@string.parse_int(value) catch { _ => return None })
    None => None
  }
}

///|
priv enum RequestBodyReadOutcome {
  Body(Bytes)
  RequestRejected
}

///|
fn next_native_request_body_chunk_size(limit : Int, total : Int) -> Int {
  let remaining = limit - total
  if remaining >= 1024 {
    1024
  } else {
    remaining + 1
  }
}

///|
test "next_native_request_body_chunk_size returns 1024 when remaining >= 1024" {
  inspect(next_native_request_body_chunk_size(2048, 0), content="1024")
  inspect(next_native_request_body_chunk_size(2048, 1024), content="1024")
  inspect(next_native_request_body_chunk_size(4096, 2000), content="1024")
}

///|
test "next_native_request_body_chunk_size returns remaining + 1 when remaining < 1024" {
  inspect(next_native_request_body_chunk_size(1000, 0), content="1001")
  inspect(next_native_request_body_chunk_size(2048, 1500), content="549")
  inspect(next_native_request_body_chunk_size(100, 99), content="2")
  inspect(next_native_request_body_chunk_size(100, 100), content="1")
}

///|
test "native request body limit helpers handle int max boundaries" {
  let max_int = 2_147_483_647
  inspect(next_native_request_body_chunk_size(max_int, 0), content="1024")
  inspect(
    native_request_body_chunk_exceeds_limit(max_int, max_int, 1),
    content="true",
  )
  inspect(
    native_request_body_chunk_exceeds_limit(max_int, max_int - 1, 1),
    content="false",
  )
}

///|
fn native_request_body_chunk_exceeds_limit(
  limit : Int,
  total : Int,
  chunk_length : Int,
) -> Bool {
  chunk_length > limit - total
}

///|
test "native_request_body_chunk_exceeds_limit returns true when chunk exceeds remaining" {
  inspect(native_request_body_chunk_exceeds_limit(100, 90, 11), content="true")
  inspect(native_request_body_chunk_exceeds_limit(100, 100, 1), content="true")
}

///|
test "native_request_body_chunk_exceeds_limit returns false when chunk fits" {
  inspect(native_request_body_chunk_exceeds_limit(100, 90, 10), content="false")
  inspect(native_request_body_chunk_exceeds_limit(100, 0, 100), content="false")
  inspect(native_request_body_chunk_exceeds_limit(100, 50, 1), content="false")
}

///|
async fn read_request_body_async(
  request : @http.Request,
  body_reader : &@io.Reader,
  conn : @http.ServerConnection,
  max_request_body_bytes : Int?,
) -> RequestBodyReadOutcome {
  match max_request_body_bytes {
    None => Body(body_reader.read_all().binary())
    Some(limit) => {
      match request_content_length(request) {
        Some(content_length) if content_length > limit => {
          send_request_entity_too_large_async(request, conn)
          return RequestRejected
        }
        _ => ()
      }
      let buffer = @buffer.new()
      let mut total = 0
      for ;; {
        let next_chunk_size = next_native_request_body_chunk_size(limit, total)
        guard body_reader.read_some(max_len=next_chunk_size) is Some(chunk) else {
          return Body(buffer.contents())
        }
        if native_request_body_chunk_exceeds_limit(limit, total, chunk.length()) {
          send_request_entity_too_large_async(request, conn)
          return RequestRejected
        }
        total += chunk.length()
        buffer.write_bytes(chunk)
      }
    }
  }
}

///|
async fn read_request_body_with_policy_async(
  request : @http.Request,
  body_reader : &@io.Reader,
  conn : @http.ServerConnection,
  max_request_body_bytes : Int?,
  request_body_read_timeout_ms : Int?,
) -> RequestBodyReadOutcome {
  match request_body_read_timeout_ms {
    Some(request_body_read_timeout_ms) =>
      match
        @async.with_timeout_opt(request_body_read_timeout_ms, () => {
          read_request_body_async(
            request, body_reader, conn, max_request_body_bytes,
          )
        }) {
        Some(outcome) => outcome
        None => {
          send_request_timeout_async(request, conn)
          RequestRejected
        }
      }
    None =>
      read_request_body_async(
        request, body_reader, conn, max_request_body_bytes,
      )
  }
}

///|
/// Dispatches one inbound HTTP request through the Mocket pipeline.
///
/// Called per-request by `run_native_server` (and by the graceful-shutdown
/// accept loop in `serve_on`). Runs to completion once per request: this
/// function does not itself loop, keep-alive reuse is driven by the caller.
///
/// Pipeline phases, in order:
///
///   1. **WebSocket dispatch.** If the request looks like a WS handshake AND
///      a matching `ws` route exists, hand off to `handle_websocket_route_async`
///      and return (the response is sent inside the WS handler). A strict
///      upgrade request with no matching route yields `404`. A non-strict
///      lookalike with no match falls through to the HTTP pipeline.
///   2. **Body reading.** Skipped entirely for bodyless methods
///      (GET/HEAD/DELETE/OPTIONS/TRACE) unless Content-Length > 0 or
///      Transfer-Encoding: chunked — chunked bodies MUST still be consumed
///      to keep the keep-alive stream in sync. Otherwise reads up to
///      `max_request_body_bytes` with `request_body_read_timeout_ms`; on
///      violation the helper sends `413` or `408` and we return early.
///   3. **Route lookup.** `lookup_http_route` returns one of:
///      `Found` (normal), `MethodNotAllowed` (synthesize 405),
///      `Options` (synthesize 204 + Allow for CORS-style preflight), or
///      `NotFound` (user's `not_found_handler` if set, else default 404).
///   4. **Handler + middleware execution.** Run the onion chain, optionally
///      wrapped in `with_timeout_opt(handler_timeout_ms)`. The timeout covers
///      handler execution only, NOT response transmission — otherwise a late
///      timeout could tear down a partially-sent response and corrupt the
///      keep-alive framing. A timed-out handler yields `504 Gateway Timeout`.
///   5. **Response transmission.** `send_response_async` finalizes headers
///      (cookies, Date) and writes to the socket.
///
/// The function does not raise; transport/IO errors surface through
/// `send_response_async`'s early returns and are caught by the keep-alive
/// loop in `serve_on` (which closes the connection on error).
async fn Mocket::handle_request(
  self : Mocket,
  ws_runtime_id : String,
  request : @http.Request,
  body_reader : &@io.Reader,
  conn : @http.ServerConnection,
  options : NativeServeOptions,
) -> Unit {
  // Target is the path *without* query string; query-string parsing happens
  // lazily inside the handler via MocketEvent helpers.
  let request_path = @httputil.request_target_path(request.path)

  // -------------------------------------------------------------------------
  // Phase 1: WebSocket upgrade dispatch
  // -------------------------------------------------------------------------
  // Two-tier detection: a "strict" check that the upgrade headers are
  // well-formed, and a cheaper "looks-like" heuristic. We only run the
  // heuristic when the app actually has WS routes registered — otherwise
  // every HTTP request would pay for handshake inspection.
  let strict_websocket_upgrade = request.is_websocket_upgrade_request()
  let has_ws_routes = !self.ws_static_routes.is_empty() ||
    !self.ws_dynamic_routes.is_empty()
  let websocket_like_request = if strict_websocket_upgrade {
    true
  } else if has_ws_routes {
    looks_like_websocket_handshake_request(request)
  } else {
    false
  }
  if websocket_like_request {
    // Resolve WS option defaults here (not in the handler) so per-connection
    // settings are captured once before entering the peer loop.
    let websocket_max_message_bytes = options.websocket_max_message_bytes
    let websocket_outgoing_queue_capacity = options.websocket_outgoing_queue_capacity.unwrap_or(
      DEFAULT_NATIVE_WS_OUTGOING_QUEUE_CAPACITY,
    )
    let websocket_overflow_policy = options.websocket_overflow_policy.unwrap_or(
      DropOldest,
    )
    let websocket_read_timeout_ms = options.websocket_read_timeout_ms
    match self.find_ws_route(request_path) {
      Some((ws_handler, route_params)) => {
        // Copy StringView params into owned Strings: the peer outlives the
        // request buffer, so borrowed views would dangle.
        let ws_params : Map[String, String] = {}
        route_params.each((k, v) => ws_params.set(k, v.to_string()))
        handle_websocket_route_async(
          ws_runtime_id, request, conn, ws_handler, ws_params, websocket_max_message_bytes,
          websocket_outgoing_queue_capacity, websocket_overflow_policy, websocket_read_timeout_ms,
        )
        return
      }
      // Strict upgrade with no matching route: client asked for WS explicitly,
      // we refuse with 404 (and connection close, inside send_not_found_async).
      None if strict_websocket_upgrade => {
        send_not_found_async(request, conn)
        return
      }
      // Non-strict lookalike with no match: treat as a plain HTTP request,
      // fall through to the normal pipeline below.
      None => ()
    }
  }

  // -------------------------------------------------------------------------
  // Phase 2: Request body reading
  // -------------------------------------------------------------------------
  let http_method_text = request_method_to_string(request.meth)
  // Skip body reading for methods that typically have no body, UNLESS:
  //   - Content-Length > 0 (client explicitly sent a body), or
  //   - Transfer-Encoding: chunked (chunked bodies MUST be consumed, even
  //     on GET/HEAD/etc., or the next request on this keep-alive connection
  //     will parse the chunk trailer as a new request line).
  let has_content_length = request_content_length(request) is Some(len) &&
    len > 0
  let is_chunked = header_contains_token_case_insensitive(
    request.headers,
    "transfer-encoding",
    "chunked",
  )
  let has_body_hint = has_content_length || is_chunked
  let request_body : Bytes = if !has_body_hint &&
    request.meth is (Get | Head | Delete | Options | Trace) {
    b""
  } else {
    let max_request_body_bytes = options.max_request_body_bytes
    let request_body_read_timeout_ms = options.request_body_read_timeout_ms
    // read_request_body_with_policy_async handles both limits and sends the
    // appropriate 413/408 response itself; we just early-return if rejected.
    match
      read_request_body_with_policy_async(
        request, body_reader, conn, max_request_body_bytes, request_body_read_timeout_ms,
      ) {
      Body(request_body) => request_body
      RequestRejected => return
    }
  }

  // -------------------------------------------------------------------------
  // Phase 3: Route lookup
  // -------------------------------------------------------------------------
  // lookup_http_route distinguishes four outcomes. Only `Found` uses the
  // user's handler; the others synthesize framework-level responses:
  //   - MethodNotAllowed: path matches *some* method, but not this one (405)
  //   - Options: CORS-style preflight — synthesize 204 + Allow header
  //   - NotFound: no path match — prefer user's not_found_handler if set
  let (params, handler) = match
    self.lookup_http_route(http_method_text, request_path) {
    Found(matched_handler, matched_params) => (matched_params, matched_handler)
    MethodNotAllowed(allow) => ({}, method_not_allowed_handler(allow))
    Options(allow) => ({}, options_handler(allow))
    NotFound =>
      match self.not_found_handler {
        Some(handler) => ({}, handler)
        None => ({}, handle_not_found())
      }
  }

  // -------------------------------------------------------------------------
  // Phase 4: Handler execution (with optional timeout)
  // -------------------------------------------------------------------------
  // Build the user-facing event. `res` starts as 200 OK; the handler mutates
  // it (status_code, headers, cookies) and returns a Responder for the body.
  let event = {
    req: HttpRequest::from_method_string(
      http_method_text,
      request.path,
      copy_async_headers(request.headers),
      request_body,
    ),
    res: HttpResponse(status_code=OK),
    params,
  }
  match options.handler_timeout_ms {
    Some(timeout_ms) =>
      // IMPORTANT: the timeout wraps only the handler+middleware chain, not
      // send_response_async. If transmission were inside the timeout and the
      // timeout fired mid-write, we'd leave a truncated response on the wire
      // and desync the keep-alive stream. Timing out strictly before any
      // bytes are sent lets us fall back to a clean 504 response.
      match
        @async.with_timeout_opt(timeout_ms, () => {
          execute_middlewares(self.middlewares, event, handler)
        }) {
        Some(responder) =>
          send_response_async(request, conn, event.res, responder)
        None => send_gateway_timeout_async(request, conn)
      }
    None => {
      // No timeout: run handler, then transmit. Phase 5 happens inline here.
      let responder = execute_middlewares(self.middlewares, event, handler)
      send_response_async(request, conn, event.res, responder)
    }
  }
}

///|
async fn run_native_server(
  app : Mocket,
  ws_runtime_id : String,
  server : @http.Server,
  options : NativeServeOptions,
) -> Unit {
  match options.max_connections {
    Some(max_connections) =>
      server.run_forever(allow_failure=true, max_connections~, (
        request,
        body_reader,
        conn,
      ) => {
        app.handle_request(ws_runtime_id, request, body_reader, conn, options)
      })
    None =>
      server.run_forever(allow_failure=true, (request, body_reader, conn) => {
        app.handle_request(ws_runtime_id, request, body_reader, conn, options)
      })
  }
}

///|
async fn wait_for_shutdown_signal(shutdown : @async.Queue[Unit]) -> Unit {
  ignore(try? shutdown.get())
}

///|
/// Starts serving HTTP requests on the given server.
/// `max_connections`, if present, limits the number of client connections
/// handled in parallel by the underlying `@http.Server`.
/// `max_request_body_bytes`, if present, rejects oversized request bodies
/// with `413 Request Entity Too Large`.
/// `request_body_read_timeout_ms`, if present, rejects slow request bodies
/// with `408 Request Timeout`.
/// `websocket_max_message_bytes`, if present, closes websocket connections
/// with `1009 MessageTooBig` when an inbound message exceeds that many bytes.
/// `websocket_outgoing_queue_capacity`, if present, bounds buffered outbound
/// websocket messages per connection.
/// `websocket_overflow_policy`, if present, chooses whether a full outbound
/// websocket queue drops the oldest or latest message.
/// `websocket_read_timeout_ms`, if present, closes websocket connections
/// after that many milliseconds waiting for the next inbound message.
/// When `shutdown` is supplied, serving stops once the queue receives a unit
/// or is closed. `shutdown.put(())` wakes one waiter; `shutdown.close()`
/// broadcasts to all waiters. When `shutdown_timeout_ms` is set, shutdown is
/// graceful: the server stops accepting new connections and waits up to that
/// many milliseconds for in-flight requests to complete before force-cancelling.
/// Otherwise shutdown is cancellation-based (active requests are aborted
/// immediately).
pub async fn Mocket::serve_on(
  self : Mocket,
  server : @http.Server,
  shutdown? : @async.Queue[Unit],
  options? : NativeServeOptions = NativeServeOptions(),
) -> Unit {
  let ws_runtime_id = next_ws_serve_runtime_id(self)
  defer cleanup_native_ws_runtime(ws_runtime_id)
  match shutdown {
    None => run_native_server(self, ws_runtime_id, server, options)
    Some(shutdown) =>
      match options.shutdown_timeout_ms {
        Some(timeout_ms) => {
          // Graceful shutdown with manual accept loop.
          // Architecture: inner task group tracks handler tasks; outer group
          // provides the cancellation boundary for the hard timeout.
          //
          // Timeline:
          // 1. Accept loop runs, spawning handler tasks into inner group.
          // 2. Shutdown signal → set draining flag, close server.
          // 3. Accept loop exits (accept fails after close).
          // 4. Inner group waits for handler tasks to finish current requests.
          // 5. Hard timeout (started AFTER shutdown) cancels everything.
          let sem : @async.Semaphore? = match options.max_connections {
            Some(n) => Some(@async.Semaphore::new(n))
            None => None
          }
          let draining : Ref[Bool] = Ref::new(false)
          let handlers_drained : @async.Queue[Unit] = @async.Queue::new(
            kind=Unbounded,
          )
          @async.with_task_group(outer => {
            // Inner group: accept loop + handler tasks
            outer.spawn_bg(no_wait=true, allow_failure=true, () => {
              @async.with_task_group(inner => {
                // Accept loop is the main function of inner group.
                // When it exits, inner group waits for handler children.
                for ;; {
                  let conn_result : Result[
                    (@http.ServerConnection, @socket.Addr),
                    Error,
                  ] = try? server.accept()
                  match conn_result {
                    Err(_) => break // server closed, stop accepting
                    Ok((conn, _addr)) => {
                      match sem {
                        Some(s) => s.acquire()
                        None => ()
                      }
                      inner.spawn_bg(allow_failure=true, () => {
                        defer (match sem {
                          Some(s) => s.release()
                          None => ()
                        })
                        // Keep-alive loop: check draining after each request
                        for ;; {
                          let req_result : Result[@http.Request, Error] = try? conn.read_request()
                          match req_result {
                            Ok(request) => {
                              let body_reader : &@io.Reader = conn
                              self.handle_request(
                                ws_runtime_id, request, body_reader, conn, options,
                              ) catch {
                                _ => {
                                  conn.close()
                                  break
                                }
                              }
                              if draining.val {
                                conn.close()
                                break
                              }
                            }
                            Err(_) => {
                              conn.close()
                              break
                            }
                          }
                        }
                      })
                    }
                  }
                }
              })
              // Inner group done: all handlers have finished
              handlers_drained.put(())
            })
            // Outer main: wait for shutdown, then drain with timeout
            wait_for_shutdown_signal(shutdown)
            draining.val = true
            server.close()
            // Timeout starts NOW (after shutdown signal, not from boot)
            @async.any([
              () => ignore(try? handlers_drained.get()),
              () => @async.sleep(timeout_ms),
            ])
            // Outer main returns → outer group cancels inner (no_wait=true)
          })
        }
        None =>
          // Default: cancellation-based (abort active requests)
          @async.any([
            () => run_native_server(self, ws_runtime_id, server, options),
            () => wait_for_shutdown_signal(shutdown),
          ])
      }
  }
}

///|
/// Starts serving HTTP requests on the given port.
/// `max_connections`, if present, limits the number of client connections
/// handled in parallel by the underlying `@http.Server`.
/// `max_request_body_bytes`, if present, rejects oversized request bodies
/// with `413 Request Entity Too Large`.
/// `request_body_read_timeout_ms`, if present, rejects slow request bodies
/// with `408 Request Timeout`.
/// `websocket_max_message_bytes`, if present, closes websocket connections
/// with `1009 MessageTooBig` when an inbound message exceeds that many bytes.
/// `websocket_outgoing_queue_capacity`, if present, bounds buffered outbound
/// websocket messages per connection.
/// `websocket_overflow_policy`, if present, chooses whether a full outbound
/// websocket queue drops the oldest or latest message.
/// `websocket_read_timeout_ms`, if present, closes websocket connections
/// after that many milliseconds waiting for the next inbound message.
/// When `shutdown` is supplied, serving stops once the queue receives a unit
/// or is closed. See `serve_on` for shutdown semantics.
pub async fn Mocket::serve(
  self : Mocket,
  port~ : Int,
  shutdown? : @async.Queue[Unit],
  options? : NativeServeOptions = NativeServeOptions(),
) -> Unit {
  let addr = @socket.Addr::parse("0.0.0.0:\{port}")
  let server = @http.Server(addr, reuse_addr=true)
  self.serve_on(server, shutdown?, options~)
}
