///|
/// The event passed to each HTTP handler, bundling the request, response, and route parameters.
pub(all) struct Event {
  /// The incoming HTTP request (method, URL, headers, body).
  req : HttpRequest
  /// The outgoing HTTP response being built (status, headers, cookies, body).
  res : HttpResponse
  /// Route parameters extracted from the matched URL pattern (e.g., `":id" => "42"`).
  params : Map[String, StringView]
}

///|
/// Parses the request body as JSON and deserializes into type `T`.
/// Shorthand for `event.req.json()`.
pub fn[T : @json.FromJson] Event::json(self : Event) -> T raise {
  self.req.json()
}

///|
/// Tries to parse the request body as JSON, returning `Ok(T)` on success
/// or `Err(message)` on failure. Shorthand for `event.req.try_json()`.
pub fn[T : @json.FromJson] Event::try_json(self : Event) -> Result[T, String] {
  self.req.try_json()
}

///|
/// Returns the request ID for this event, or `None` if the `request_id`
/// middleware from `bobzhang/crescent/middleware` is not active.
pub fn Event::request_id(self : Event) -> String? {
  self.req.get_header("X-Request-Id")
}
