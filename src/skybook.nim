import tables, strutils, json, types, os, algorithm
import asynchttpserver, asyncdispatch, uri

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

proc dump_table() {.gcsafe.} =
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

proc getQueryParam(params: openArray[(string, string)], key: string): string =
  for (k, v) in params:
    if k == key: return v
  return ""

proc handleRequest(req: Request) {.async, gcsafe.} =
  var params: seq[(string, string)]
  for k, v in decodeQuery(req.url.query):
    params.add((k, v))
  case req.reqMethod
  of HttpGet:
    case req.url.path
    of "/":
      await req.respond(Http200, index_html)
    of "/a":
      await req.respond(Http200, index_html)
    of "/style.css":
      await req.respond(Http200, style_css, newHttpHeaders([("Content-Type", "text/css")]))
    of "/app.js":
      await req.respond(Http200, script_js, newHttpHeaders([("Content-Type", "application/javascript")]))
    of "/api/tags":
      var tagSet: seq[string]
      for v in bookmarks_table.values():
        for t in v.tags.split(","):
          let tag = t.strip(chars={' '})
          if tag != "" and tag notin tagSet:
            tagSet.add(tag)
      sort(tagSet, system.cmp[string])
      await req.respond(Http200, $(%* tagSet), newHttpHeaders([("Content-Type", "application/json")]))
    of "/api/bookmarks":
      var
        offset = 0
        limit = 10000
        q = getQueryParam(params, "q")
        tag = getQueryParam(params, "tag")
      try:
        let offsetStr = getQueryParam(params, "offset")
        let limitStr = getQueryParam(params, "limit")
        if offsetStr != "": offset = parseInt(offsetStr)
        if limitStr != "": limit = parseInt(limitStr)
      except: discard
      var r = get_bookmarks(bookmarks_table, q=q, tag=tag,
                            offset=offset, limit=limit)
      await req.respond(Http200, $r, newHttpHeaders([("Content-Type", "application/json")]))
    else:
      await req.respond(Http404, "Not Found")
  of HttpPost:
    case req.url.path
    of "/api/bookmarks":
      var body = parseJson(req.body)
      var tbm = body.to(BookMark)
      bookmarks_table[tbm.url] = tbm
      dump_table()
      await req.respond(Http200, """{"status":"ok"}""", newHttpHeaders([("Content-Type", "application/json")]))
    of "/api/bookmarks/delete":
      var body = parseJson(req.body)
      var url = body["url"].str
      if url in bookmarks_table:
        bookmarks_table.del(url)
        dump_table()
      await req.respond(Http200, """{"status":"ok"}""", newHttpHeaders([("Content-Type", "application/json")]))
    of "/api/bookmarks/delete/batch":
      var body = parseJson(req.body)
      var urls: seq[string]
      for item in body["urls"]:
        urls.add(item.str)
      for url in urls:
        if url in bookmarks_table:
          bookmarks_table.del(url)
      dump_table()
      var r = %* {"status": "ok", "count": urls.len}
      await req.respond(Http200, $r, newHttpHeaders([("Content-Type", "application/json")]))
    else:
      await req.respond(Http404, "Not Found")
  else:
    await req.respond(Http405, "Method Not Allowed")

when isMainModule:
  echo "Listening on http://127.0.0.1:5000"
  let server = newAsyncHttpServer()
  let handler = proc (req: Request) {.async, gcsafe.} =
    await handleRequest(req)
  waitFor server.serve(Port(5000), handler, "127.0.0.1")
