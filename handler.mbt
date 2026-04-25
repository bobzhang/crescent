///|
/// The async handler type for HTTP route callbacks.
pub(all) struct HttpHandler(async (Event) -> &Responder noraise)
