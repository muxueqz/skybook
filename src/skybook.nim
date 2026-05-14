import tables, strutils, json, types, os, algorithm, locks
import asynchttpserver, asyncdispatch, uri, parseopt

const
  style_css = staticRead("./frontend/style.css")
  script_js = staticRead("./frontend/app.js")
  index_html = staticRead("./frontend/app.html")

var
  bookmarks_file_name = "bookmarks.db"
  bookmarks_table = initTable[string, BookMark]()

var dbLock: Lock
const maxBodySize = 1_048_576

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
  let tmpFile = bookmarks_file_name & ".tmp"
  writeFile(tmpFile, s)
  moveFile(tmpFile, bookmarks_file_name)

proc get_bookmarks(bookmarks_table: Table, q= "", tag= "",
                   offset= 0, limit= 0): JsonNode =
  var all: seq[BookMark]
  let filterTags = if tag != "": tag.split(",") else: @[]
  let hasQ = q != ""
  let hasTag = filterTags.len > 0
  for v in bookmarks_table.values():
    if hasTag:
      let vTags = v.tags.split(",")
      var tagHit = true
      for ft in filterTags:
        let ftTrimmed = ft.strip()
        if ftTrimmed == "": continue
        var found = false
        for vt in vTags:
          if vt.strip() == ftTrimmed:
            found = true
            break
        if not found:
          tagHit = false
          break
      if not tagHit:
        continue
    if hasQ:
      var lower_q = q.toLower
      if lower_q notin v.name.toLower and
         lower_q notin v.note.toLower and
         lower_q notin v.tags.toLower:
        continue
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
      acquire(dbLock)
      var tagSet: seq[string]
      for v in bookmarks_table.values():
        for t in v.tags.split(","):
          let tag = t.strip(chars={' '})
          if tag != "" and tag notin tagSet:
            tagSet.add(tag)
      release(dbLock)
      sort(tagSet, system.cmp[string])
      await req.respond(Http200, $(%* tagSet), newHttpHeaders([("Content-Type", "application/json")]))
    of "/api/bookmarks":
      var
        offset = 0
        limit = 50
        q = getQueryParam(params, "q")
        tag = getQueryParam(params, "tag")
      try:
        let offsetStr = getQueryParam(params, "offset")
        let limitStr = getQueryParam(params, "limit")
        if offsetStr != "": offset = parseInt(offsetStr)
        if limitStr != "": limit = parseInt(limitStr)
      except: discard
      acquire(dbLock)
      var r = get_bookmarks(bookmarks_table, q=q, tag=tag,
                            offset=offset, limit=limit)
      release(dbLock)
      await req.respond(Http200, $r, newHttpHeaders([("Content-Type", "application/json")]))
    else:
      await req.respond(Http404, "Not Found")
  of HttpPost:
    if req.body.len > maxBodySize:
      await req.respond(Http413, """{"status":"error","msg":"Request too large"}""", newHttpHeaders([("Content-Type", "application/json")]))
      return
    case req.url.path
    of "/api/bookmarks":
      try:
        var body = parseJson(req.body)
        var tbm = body.to(BookMark)
        acquire(dbLock)
        bookmarks_table[tbm.url] = tbm
        dump_table()
        release(dbLock)
        await req.respond(Http200, """{"status":"ok"}""", newHttpHeaders([("Content-Type", "application/json")]))
      except:
        await req.respond(Http400, """{"status":"error","msg":"Invalid request"}""", newHttpHeaders([("Content-Type", "application/json")]))
    of "/api/bookmarks/delete":
      try:
        var body = parseJson(req.body)
        var url = body["url"].str
        acquire(dbLock)
        if url in bookmarks_table:
          bookmarks_table.del(url)
          dump_table()
        release(dbLock)
        await req.respond(Http200, """{"status":"ok"}""", newHttpHeaders([("Content-Type", "application/json")]))
      except:
        await req.respond(Http400, """{"status":"error","msg":"Invalid request"}""", newHttpHeaders([("Content-Type", "application/json")]))
    of "/api/bookmarks/delete/batch":
      try:
        var body = parseJson(req.body)
        var urls: seq[string]
        for item in body["urls"]:
          urls.add(item.str)
        acquire(dbLock)
        for url in urls:
          if url in bookmarks_table:
            bookmarks_table.del(url)
        dump_table()
        release(dbLock)
        var r = %* {"status": "ok", "count": urls.len}
        await req.respond(Http200, $r, newHttpHeaders([("Content-Type", "application/json")]))
      except:
        await req.respond(Http400, """{"status":"error","msg":"Invalid request"}""", newHttpHeaders([("Content-Type", "application/json")]))
    else:
      await req.respond(Http404, "Not Found")
  else:
    await req.respond(Http405, "Method Not Allowed")

when isMainModule:
  var port = 5000
  var address = "127.0.0.1"
  var dbFile = "bookmarks.db"

  var optKey = ""
  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      if val != "":
        case key
        of "port", "p": port = parseInt(val)
        of "address", "a": address = val
        of "db", "d": dbFile = val
        else: discard
      else:
        optKey = key
    of cmdArgument:
      if optKey != "":
        case optKey
        of "port", "p": port = parseInt(key)
        of "address", "a": address = key
        of "db", "d": dbFile = key
        else: discard
        optKey = ""
    else: discard

  bookmarks_file_name = dbFile
  initLock(dbLock)
  load_database()

  echo "Listening on http://" & address & ":" & $port
  let server = newAsyncHttpServer()
  let handler = proc (req: Request) {.async, gcsafe.} =
    await handleRequest(req)
  waitFor server.serve(Port(port), handler, address)
