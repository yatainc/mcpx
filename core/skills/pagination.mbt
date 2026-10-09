///|
// The first page is fetched outside this loop, so directory fallback cannot
// catch a failure from a subsequent page. Cursors are opaque, including "".
async fn collect_pages(
  first : Json,
  fetch_next : async (String) -> Json,
  items_key~ : String,
) -> Array[Json] {
  let pages = []
  let seen = Map([])
  let mut remaining = 100_000
  for page = first {
    guard page is Object(fields) && fields.get(items_key) is Some(Array(items)) else {
      raise @protocol.InvalidResponse("paginated result requires " + items_key)
    }
    if items.length() > remaining {
      raise @protocol.InvalidResponse("retrieval exceeds 100000 items")
    }
    remaining -= items.length()
    pages.push(page)
    match page {
      { "nextCursor"? : None, .. } => break pages
      { "nextCursor": String(cursor), .. } => {
        if pages.length() >= 1000 {
          raise @protocol.InvalidResponse("retrieval exceeds 1000 pages")
        }
        if seen.contains(cursor) {
          raise @protocol.InvalidResponse("retrieval cursor repeated")
        }
        seen[cursor] = ()
        let next = fetch_next(cursor)
        continue next
      }
      _ => raise @protocol.InvalidResponse("nextCursor must be a string")
    }
  }
}
