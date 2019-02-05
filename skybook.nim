import tables
import strutils
import htmlgen
import jester
import json
from uri import decodeUrl

settings:
  port = Port(5000)
  bindAddr = "127.0.0.1"
  staticDir = "./public"

let bootstrap_import = """
<!-- 最新版本的 Bootstrap 核心 CSS 文件 -->
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@3.3.7/dist/css/bootstrap.min.css" integrity="sha384-BVYiiSIFeK1dGmJRAkycuHAHRg32OmUcww7on3RYdg4Va+PmSTsz/K68vbdEjh4u" crossorigin="anonymous">

<!-- 可选的 Bootstrap 主题文件（一般不用引入） -->
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@3.3.7/dist/css/bootstrap-theme.min.css" integrity="sha384-rHyoN1iRsVXV4nD0JutlnGaslCJuC7uwjduW9SVrLvRYooPp2bWYgmgJQIXwl/Sp" crossorigin="anonymous">

<!-- 最新的 Bootstrap 核心 JavaScript 文件 -->
<script src="https://cdn.jsdelivr.net/npm/bootstrap@3.3.7/dist/js/bootstrap.min.js" integrity="sha384-Tc5IQib027qvyjSMfHjOMaLkfuWVxZxUPnCJA7l2mCWNIpG9mGCD8wGNIcPD7Txa" crossorigin="anonymous"></script>
"""

type
  BookMark = object
    url, name, note: string
    tags: string

var bookmarks_table = initTable[string, BookMark]()

var
  bookmarks_file_name = "bookmarks.db"
  bookmarks_file: File
try:
  bookmarks_file = open(bookmarks_file_name, fmReadWriteExisting)
except IOError:
  bookmarks_file = open(bookmarks_file_name, fmWrite)

for line in bookmarks_file.lines:
  var jsonNode = parseJson(line)
  var tbm = jsonNode.to(BookMark)
  bookmarks_table[tbm.url] = tbm

proc dump_table(file_name: string,
    bookmarks_table: Table) =
  var s = ""
  for v in bookmarks_table.values():
    var dump_line = %* v
    s.add $dump_line & "\n"
  writeFile(file_name, s)

routes:
  get "/":
    var bookmarks_result: seq[string]

    for v in bookmarks_table.values():
      var url = v.url
      var name = v.name
      bookmarks_result.add(
        h4(
        li(a(href=url, strong(name))),
        "<BR>tags:", v.tags,
        "<BR>note:", v.note.replace("\n", "<BR>"))
        )
      
    resp html(
      head(bootstrap_import),
      `div`(class = "container center-block",
        h1("BookMarks:"),
        bookmarks_result.join("\n")
      )
      )
  get "/q=@search_str":
    var bookmarks_result: seq[string]

    var search_str = @"search_str"
    for v in bookmarks_table.values():
      var url = v.url
      var name = v.name
      if search_str in name:
        bookmarks_result.add(
          h4(
          li(a(href=url, name)),
          "<BR>tags:", v.tags,
          "<BR>note:", v.note.replace("\n", "<BR>"))
          )
      
    resp html(
      head(bootstrap_import),
      `div`(class = "container center-block",
        h1("BookMarks:"),
        bookmarks_result.join("\n")
      )
      )
  post "/":
    var
      url = @"url"
      name = @"name"
      tags = @"tags"
      note = @"note"

    var tbm : BookMark
    tbm.url = url
    tbm.name = name
    tbm.note = note
    tbm.tags = tags

    if url in bookmarks_table:
      echo url, bookmarks_table[url]
      echo "dump full"
      bookmarks_table[url] = tbm
      dump_table(bookmarks_file_name, bookmarks_table)
    else:
      var item = %* tbm
      bookmarks_file.setFilePos(0, fspEnd)
      bookmarks_file.writeLine(item)
      flushFile(bookmarks_file)

    bookmarks_table[url] = tbm

    resp html(
      h1("Add Success"),
      h1(@"name",
      a(href=url)
      )
      )
  get "/a":
    var
      url = decodeUrl request.params["url"]
      name = decodeUrl request.params["name"]
      note = decodeUrl request.params["note"]

      operation = "Add BookMark"
      tags: string
    if url in bookmarks_table:
      name = bookmarks_table[url].name
      note = bookmarks_table[url].note
      tags = bookmarks_table[url].tags
      operation = "Update BookMark"
    var input_textarea = """
       <label for="note">note:</label>
      <textarea class="form-control" name="note" rows="3">$1</textarea>
      """ % (note)

    resp html(
      head(bootstrap_import),
      `div`(class = "container center-block input-group",
      h1(operation),
      h1(
         form(action = "/", Method="post", `accept - charset` = "Content-Type",
         "name:", input(type = "text", name= "name", value = name, class = "form-control"),
         br(),
         "url:", input(type = "url", name= "url", value = url, class = "form-control"),
         br(),
         "tags:", input(type = "text", name= "tags", value = tags, class = "form-control"),
         br(),
         input_textarea,
         br(),
         input(type = "submit"),
           )
      )
      )
      )
