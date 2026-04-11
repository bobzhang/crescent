///|
test "get_cookie supports case-insensitive header lookup and delete_cookie expires values" {
  let req_lower = @crescent.HttpRequest(
    Get,
    "/",
    { "cookie": "session=abc123; theme=dark" },
    raw_body=b"",
  )
  match req_lower.get_cookie("session") {
    Some(cookie) => assert_eq(cookie.value, "abc123")
    None => fail("Expected session cookie")
  }
  let req_mixed = @crescent.HttpRequest(
    Get,
    "/",
    { "CoOkIe": "theme=dark" },
    raw_body=b"",
  )
  match req_mixed.get_cookie("theme") {
    Some(cookie) => assert_eq(cookie.value, "dark")
    None => fail("Expected theme cookie")
  }
  assert_eq(req_mixed.get_cookie("missing"), None)
  let res = HttpResponse::new(status_code=OK)
  res.delete_cookie("session")
  match res.cookies.get("session") {
    Some(cookie) => {
      assert_eq(cookie.value, "")
      assert_eq(cookie.max_age, Some(0))
    }
    None => fail("Expected deleted session cookie")
  }
}
