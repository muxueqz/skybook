import tables, strutils, jester, json, types, os
from uri import decodeUrl

settings:
  port = Port(5000)
  bindAddr = "127.0.0.1"
  staticDir = "./public"
  reusePort = false

const
  style_css = staticRead("./frontend/style.css")
  script_js = staticRead("./frontend/app.js")
  index_html = staticRead("./frontend/app.html")

var bookmarks_table = initTable[string, BookMark]()

var
  bookmarks_file_name = "bookmarks.db"
  bookmarks_file: File
try:
  bookmarks_file = open(bookmarks_file_name, fmReadWriteExisting)
  for line in bookmarks_file.lines:
    var jsonNode = parseJson(line)
    var tbm = jsonNode.to(BookMark)
    bookmarks_table[tbm.url] = tbm
except:
  try:
    echo "create 1"
    bookmarks_file = open(bookmarks_file_name, fmWrite)
  except:
    echo "create 2"
    removeFile(bookmarks_file_name)
    bookmarks_file = open(bookmarks_file_name, fmWrite)

proc dump_table(file_name: string, bookmarks_table: Table) =
  var s = ""
  for v in bookmarks_table.values():
    var dump_line = %* v
    s.add $dump_line & "\n"
  writeFile(file_name, s)

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
    var r = get_bookmarks(bookmarks_table, q=q, tag=tag.decodeUrl,
                          offset=offset, limit=limit)
    resp $r, "application/json"
  post "/api/bookmarks":
    var body = parseJson(request.body)
    var tbm: BookMark
    tbm.url = body["url"].str
    tbm.name = body["name"].str
    tbm.note = body["note"].str
    tbm.tags = body["tags"].str
    if tbm.url in bookmarks_table:
      bookmarks_table[tbm.url] = tbm
      dump_table(bookmarks_file_name, bookmarks_table)
    else:
      var item = %* tbm
      bookmarks_file.setFilePos(0, fspEnd)
      bookmarks_file.writeLine(item)
      flushFile(bookmarks_file)
    bookmarks_table[tbm.url] = tbm
    resp """{"status":"ok"}""", "application/json"
  post "/api/bookmarks/delete":
    var body = parseJson(request.body)
    var url = body["url"].str
    if url in bookmarks_table:
      bookmarks_table.del(url)
      dump_table(bookmarks_file_name, bookmarks_table)
    resp """{"status":"ok"}""", "application/json"
  post "/api/bookmarks/delete/batch":
    var body = parseJson(request.body)
    var urls: seq[string]
    for item in body["urls"]:
      urls.add(item.str)
    for url in urls:
      if url in bookmarks_table:
        bookmarks_table.del(url)
    dump_table(bookmarks_file_name, bookmarks_table)
    var r = %* {"status": "ok", "count": urls.len}
    resp $r, "application/json"
