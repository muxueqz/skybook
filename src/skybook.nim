import tables, strutils, jester, json, types, os, algorithm, locks
from uri import decodeUrl

var tableLock: Lock
initLock(tableLock)

settings:
  port = Port(5000)
  bindAddr = "127.0.0.1"
  staticDir = "./public"
  reusePort = false

const
  style_css = staticRead("./frontend/style.css")
  script_js = staticRead("./frontend/app.js")
  index_html = staticRead("./frontend/app.html")

var
  bookmarks_file_name = "bookmarks.db"
  bookmarks_table = initTable[string, BookMark]()

proc load_database() =
  if fileExists(bookmarks_file_name):
    try:
      for line in readFile(bookmarks_file_name).splitLines:
        if line.strip() == "": continue
        let node = parseJson(line)
        bookmarks_table[node["url"].str] = node.to(BookMark)
    except:
      stderr.writeLine("Warning: could not read " & bookmarks_file_name)

proc dump_table() =
  var s = ""
  for v in bookmarks_table.values():
    s.add($(%* v) & "\n")
  writeFile(bookmarks_file_name, s)

load_database()

proc get_bookmarks(bookmarks_table: Table, q= "", tag= "",
                   offset= 0, limit= 0): JsonNode =
  var all: seq[BookMark]
  for v in bookmarks_table.values():
    var hit = false
    if tag != "":
      if tag in v.tags.split(","):
        hit = true
    elif q != "":
      var lower_q = q.toLower
      if lower_q in v.name.toLower or
         lower_q in v.note.toLower or
         lower_q in v.tags.toLower:
        hit = true
    else:
      hit = true
    if hit:
      all.add(v)
  let total = all.len
  var items: seq[BookMark]
  let endIdx = if limit > 0: min(offset + limit, total) else: total
  for i in offset ..< endIdx:
    items.add(all[i])
  return %* {"total": total, "offset": offset, "limit": limit, "items": items}

routes:
  get "/":
    resp index_html
  get "/a":
    resp index_html
  get "/style.css":
    resp style_css, "text/css"
  get "/app.js":
    resp script_js, "application/javascript"
  get "/api/tags":
    acquire(tableLock)
    var tagSet: seq[string]
    for v in bookmarks_table.values():
      for t in v.tags.split(","):
        let tag = t.strip(chars={' '})
        if tag != "" and tag notin tagSet:
          tagSet.add(tag)
    release(tableLock)
    sort(tagSet, system.cmp[string])
    resp $(%* tagSet), "application/json"
  get "/api/bookmarks":
    var
      offset = 0
      limit = 10000
      q = @"q"
      tag = @"tag"
    try:
      if @"offset" != "": offset = parseInt(@"offset")
      if @"limit" != "": limit = parseInt(@"limit")
    except: discard
    acquire(tableLock)
    var r = get_bookmarks(bookmarks_table, q=q, tag=tag.decodeUrl,
                          offset=offset, limit=limit)
    release(tableLock)
    resp $r, "application/json"
  post "/api/bookmarks":
    var body = parseJson(request.body)
    var tbm: BookMark
    tbm.url = body["url"].str
    tbm.name = body["name"].str
    tbm.note = body["note"].str
    tbm.tags = body["tags"].str
    acquire(tableLock)
    bookmarks_table[tbm.url] = tbm
    dump_table()
    release(tableLock)
    resp """{"status":"ok"}""", "application/json"
  post "/api/bookmarks/delete":
    var body = parseJson(request.body)
    var url = body["url"].str
    acquire(tableLock)
    if url in bookmarks_table:
      bookmarks_table.del(url)
      dump_table()
    release(tableLock)
    resp """{"status":"ok"}""", "application/json"
  post "/api/bookmarks/delete/batch":
    var body = parseJson(request.body)
    var urls: seq[string]
    for item in body["urls"]:
      urls.add(item.str)
    acquire(tableLock)
    for url in urls:
      if url in bookmarks_table:
        bookmarks_table.del(url)
    dump_table()
    release(tableLock)
    var r = %* {"status": "ok", "count": urls.len}
    resp $r, "application/json"
