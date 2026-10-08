///|
// The first page is fetched outside this loop, so directory fallback cannot
// catch a failure from a subsequent page. Cursors are opaque, including "".
async fn collect_pages(
  first : Json,
  fetch_next : async (String) -> Json,
) -> Array[Json] {
  let pages = [first]
  for page = first {
    match page {
      { "nextCursor"? : None, .. } => break pages
      { "nextCursor": String(cursor), .. } => {
        let next = fetch_next(cursor)
        pages.push(next)
        continue next
      }
      _ => raise @protocol.InvalidResponse("nextCursor must be a string")
    }
  }
}
