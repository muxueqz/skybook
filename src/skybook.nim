import tables
import strutils
import htmlgen
import jester
import json
from uri import decodeUrl, encodeUrl

settings:
  port = Port(5000)
  bindAddr = "127.0.0.1"
  staticDir = "./public"
  reusePort = false

let bootstrap_import = """
  <meta charset="utf-8">
  <meta http-equiv="X-UA-Compatible" content="IE=edge,chrome=1">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">

  <!-- Site Properties -->
  <title>bookmarks</title>
  <link href="https://cdn.bootcss.com/semantic-ui/2.4.1/semantic.min.css" rel="stylesheet">
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

var item_template = """
    <div class="item">
      <div class="content">
        <a class="header" href="$2">$1</a>
        <div class="meta">
          <a>Date</a>
          <a>Category</a>
        </div>
        <div class="description" style=" font-size: 1.2rem; ">
        $5
                            </div>
        <div class="extra">
          <a href="$3">
          <div class="ui right floated primary button">
          Edit
          </div>
          </a>
          $4
        </div>
      </div>
    </div>
"""
var add_template = """
<body>

<div class="ui middle aligned center aligned grid">
  <div class="column">
    <h2 class="ui teal image header">
      <div class="content">
        Add bookmark
      </div>
    </h2>
    <form class="ui large form"
    action="/" Method="post" accept-charset="Content-Type" >
      <div class="ui stacked segment">
      $1
        <input type="submit" class="ui fluid large teal submit button">
      </div>

    </form>

  </div>
</div>

</body>
"""

proc get_bookmarks(bookmarks_table: Table,
      search_str= "" ): string =
  var bookmarks_result: seq[string]
  for v in bookmarks_table.values():
    var
      url = v.url
      name = v.name
      edit_url = "http://localhost:5000/a?url=" & encodeUrl(url)
      tags = ""
      lower_search_str = search_str.toLower
    if lower_search_str in name.toLower or
      lower_search_str in v.note.toLower or
      lower_search_str in v.tags.split(",") or
      search_str == "":
      for i in v.tags.split(","):
        tags.add """
          <div class="ui label">$1</div>
          """ % ( i.strip(chars={' '}) )
      bookmarks_result.add(item_template % [
        name, url, edit_url,
        tags,
        v.note.replace("\n", "<BR>")
        ])
    
  result = html(
    head(bootstrap_import),
    `div`(class = "ui container",
      h2("bookmarks"),
      `div`(class = "ui relaxed divided items",
        bookmarks_result.join("\n")
      )
    )
    )
  # return $result

routes:
  get "/":

    resp get_bookmarks(bookmarks_table)
  get "/q=@search_str":
    var search_str = @"search_str"
    resp get_bookmarks(bookmarks_table, search_str=search_str)
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
      args = initTable[string, string]()
      operation = "Add BookMark"
      tags: string
      url = decodeUrl request.params["url"]

    args["url"] = url
    for i in "name note tags".split(" "):
      args[i] = decodeUrl request.params.getOrDefault(i, "")

    if args["url"] in bookmarks_table:
      args["name"] = bookmarks_table[url].name
      args["note"] = bookmarks_table[url].note
      args["tags"] = bookmarks_table[url].tags
      operation = "Update BookMark"
    var input_textarea = """
       <label for="note">note:</label>
      <textarea class="form-control" name="note" rows="3">$1</textarea>
      """ % (args["note"])

    var user_input = ""
    for i in "name url note tags".split(" "):
      var tmp_input: string
      if i == "note":
        tmp_input = """
            <div class="field">
              <h3 class="ui left aligned header"
                    style=" text-transform: uppercase; ">
                  $2</h3>
              <div class="ui left icon input">
                <textarea type="text" name="$2">$1</textarea>
              </div>
            </div>
            """ % [args[i], i]
      else:
        tmp_input = """
            <div class="field">
              <h3 class="ui left aligned header"
                    style=" text-transform: uppercase; ">
                  $2</h3>
              <div class="ui left icon input">
                <i class="linkify icon"></i>
                <input type="text" name="$2" value="$1" placeholder="$2">
              </div>
            </div>
            """ % [args[i], i]
      user_input.add tmp_input
    resp html(bootstrap_import,
              add_template % (user_input)
              )
