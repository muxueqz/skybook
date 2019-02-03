import strtabs
import tables
from uri import decodeUrl
import db_sqlite
import strutils
import htmlgen
import jester
import htmlparser
import xmltree  # To use '$' for XmlNode

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

var bookmarks_file = open("bookmarks.db", fmReadWriteExisting)

var html = loadHtml("bookmarks.db")
for a in html.findAll("a"):
  var href = a.attrs["href"]
  var tbm : BookMark
  tbm.url = href
  tbm.name = a.attrs["name"]
  tbm.note = a.attrs["note"]
  tbm.tags = a.attrs["tags"]
  bookmarks_table[href] = tbm

routes:
  get "/":
    var bookmarks_result: seq[string]

    for v in bookmarks_table.values():
      var url = v.url
      var name = v.name
      bookmarks_result.add(
        h4(
        li(a(href=url, name)),
        "<BR>tags:", v.tags,
        "<BR>note:", v.note)
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
          # li(a(href="http://g.cn", "nim测试"))
          li(a(href=url, name))
          )
      
    resp html(bookmarks_result.join())
  post "/":
    var url = @"url"
    var name = @"name"
    var tags = @"tags"
    var note = @"note"
    if url in bookmarks_table:
      echo "dump full"
    else:
      var item_html = """<a href="$1" tags="$2" name="$3" note="$4"></a> """ % [
        url, tags, name, note
        ]
      bookmarks_file.setFilePos(0, fspEnd)
      bookmarks_file.writeLine(item_html)
      flushFile(bookmarks_file)

    var tbm : BookMark
    tbm.url = url
    tbm.name = name
    tbm.note = note
    tbm.tags = tags
    bookmarks_table[url] = tbm
    # writeFile("bookmarks.db", item_html)
    resp html(
      h1("Add Success"),
      h1(@"name",
      a(href=url)
      )
      )
  get "/a":
    var url = decodeUrl request.params["url"]
    var name = decodeUrl request.params["name"]
    resp html(
      head(bootstrap_import),
      `div`(class = "container center-block input-group",
      h1("Add BookMarks"),
      h1(
         form(action = "/", Method="post", `accept - charset` = "Content-Type",
         "name:", input(type = "text", name= "name", value = name, class = "form-control"),
         br(),
         "url:", input(type = "text", name= "url", value = url, class = "form-control"),
         br(),
         "tags:", input(type = "text", name= "tags", class = "form-control"),
         br(),
         "note:", input(type = "text", name= "note", class = "form-control"),
         br(),
         input(type = "submit"),
           )
      )
      )
      )