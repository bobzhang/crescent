///|
fn handle_not_found() -> HttpHandler {
  (_ : Event) => HttpResponse(status_code=NotFound).body("Not Found")
}
