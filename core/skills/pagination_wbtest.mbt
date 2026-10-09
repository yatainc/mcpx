///|
async test "pagination accepts inclusive page and aggregate item boundaries" {
  let calls = Ref(0)
  let pages = collect_pages(
    { "skills": [], "nextCursor": "0" },
    _ => {
      calls.val += 1
      if calls.val == 999 {
        { "skills": [] }
      } else {
        { "skills": [], "nextCursor": calls.val.to_string().to_json() }
      }
    },
    items_key="skills",
  )
  assert_eq(pages.length(), 1000)
  let items = Array::make(50000, Json::null()).to_json()
  let pages = collect_pages(
    { "resources": items, "nextCursor": "" },
    cursor => {
      assert_eq(cursor, "")
      { "resources": items, "unknown": true }
    },
    items_key="resources",
  )
  assert_eq(pages.length(), 2)
  assert_true(pages[1] is { "unknown": True, .. })
}

///|
async test "pagination counters and nonadjacent opaque cursor loops reject before next request" {
  let calls = Ref(0)
  let rejected = try {
    ignore(
      collect_pages(
        { "skills": [], "nextCursor": "" },
        cursor => {
          calls.val += 1
          { "skills": [], "nextCursor": if cursor == "" { "a" } else { "" } }
        },
        items_key="skills",
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_eq(calls.val, 2)
  calls.val = 0
  assert_true(
    try {
      ignore(
        collect_pages(
          { "skills": [], "nextCursor": "0" },
          _ => {
            calls.val += 1
            { "skills": [], "nextCursor": calls.val.to_string().to_json() }
          },
          items_key="skills",
        ),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_eq(calls.val, 999)
  let items = Array::make(100001, Json::null())
  assert_true(
    try {
      ignore(
        collect_pages(
          { "resources": items.to_json() },
          _ => fail("no IO"),
          items_key="resources",
        ),
      )
      false
    } catch {
      _ => true
    },
  )
}
