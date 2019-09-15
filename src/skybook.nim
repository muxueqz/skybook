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

const style_css = staticRead("./main.css")

let bootstrap_import = """
  <meta charset="utf-8">
  <meta http-equiv="X-UA-Compatible" content="IE=edge,chrome=1">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">

  <!-- Site Properties -->
  <title>bookmarks</title>
<link rel="stylesheet" href="/style.css">

  <style>
  html {
    font-size: 80%;
  }
  .right {
    float: right;
  }
.navbar {
  background-color: #44679f!important;
  color: white;
}
.header {
  background-color: rgba(23,24,26,.03);
  border-bottom: 1px solid rgba(23,24,26,.125);
}
.content {
  border: 1px solid rgba(23,24,26,.125);
}
.ui.label {
    display: inline-block;
    line-height: 1;
    vertical-align: baseline;
    margin: 0 .14285714em;
    background-color: #e8e8e8;
    background-image: none;
    padding: .5833em .833em;
    color: rgba(0,0,0,.6);
    text-transform: none;
    font-weight: 700;
    font-size: 1.2rem;
    border: 0 solid transparent;
    border-radius: .28571429rem;
    -webkit-transition: background .1s ease;
    transition: background .1s ease;
}
.meta {
    color: rgba(0,0,0,.4);
}
  </style>

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

  for line in bookmarks_file.lines:
    var jsonNode = parseJson(line)
    var tbm = jsonNode.to(BookMark)
    bookmarks_table[tbm.url] = tbm
except IOError:
  bookmarks_file = open(bookmarks_file_name, fmWrite)

proc dump_table(file_name: string,
    bookmarks_table: Table) =
  var s = ""
  for v in bookmarks_table.values():
    var dump_line = %* v
    s.add $dump_line & "\n"
  writeFile(file_name, s)

        # <div class="meta">
          # <a>Date</a>
          # <a>Category</a>
        # </div>
var item_template = """
    <div class="item">
      <div class="content">
        <div class="header">
        <a href="$2">$1</a>
          <a href="http://localhost:5000/a?url=$3">
          <div class="ui right float">

<svg version="1.1" id="Capa_1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" x="0px" y="0px"
	 width="29px" height="29px" viewBox="0 0 459 459" style="enable-background:new 0 0 459 459;" xml:space="preserve">
<g>
    <path d="M328.883,89.125l107.59,107.589l-272.34,272.34L56.604,361.465L328.883,89.125z M518.113,63.177l-47.981-47.981
            c-18.543-18.543-48.653-18.543-67.259,0l-45.961,45.961l107.59,107.59l53.611-53.611
            C532.495,100.753,532.495,77.559,518.113,63.177z M0.3,512.69c-1.958,8.812,5.998,16.708,14.811,14.565l119.891-29.069
            L27.473,390.597L0.3,512.69z"/>
</g>
</svg>
          </div>
          </a>
          <a href="http://localhost:5000/delete?url=$3">
          <div class="ui right">
<svg version="1.1" id="Capa_1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" x="0px" y="0px"
	 width="29px" height="29px" viewBox="0 0 459 459" style="enable-background:new 0 0 459 459;" xml:space="preserve">
<g>
	<g id="delete">
		<path d="M76.5,408c0,28.05,22.95,51,51,51h204c28.05,0,51-22.95,51-51V102h-306V408z M408,25.5h-89.25L293.25,0h-127.5l-25.5,25.5
			H51v51h357V25.5z"/>
	</g> </g>
</svg>
          </div>
          </a>
        </div>
        <div class="description" style=" font-size: 1.2rem; ">
        $5
                            </div>
        <div class="extra">
          $4
        </div>
      </div>
    </div>
"""
var item_desc_template = """
<body>

<div class="ui middle aligned center aligned grid">
  <div class="column">
    <h2 class="ui teal image header">
      <div class="content">
        $2
      </div>
    </h2>
    <form class="ui large form"
    action="$3" Method="post" accept-charset="Content-Type" >
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
      tag= "",
      search_str= "" ): string =
  var
    bookmarks_result: seq[string]
    title: string
    count = 0
  for v in bookmarks_table.values():
    var
      url = v.url
      name = v.name
      encode_url = encodeUrl(url)
      tags = ""
      lower_search_str = search_str.toLower
      hit = false
    for i in v.tags.split(","):
      tags.add """
        <div class="ui label">
          <a href="http://localhost:5000/t=$1">$1</a>
        </div>
        """ % ( i.strip(chars={' '}) )
    if tag != "" and tag in v.tags.split(","):
      hit = true
    elif search_str == "" and tag == "":
      hit = true
    elif search_str != "":
      if lower_search_str in name.toLower or
        lower_search_str in v.note.toLower or
        lower_search_str in v.tags.split(","):
        hit = true
    
    if hit:
      bookmarks_result.add(item_template % [
        name, url, encode_url,
        tags,
        v.note.replace("\n", "<BR>")
        ])
      count += 1
  title = "Found $1 bookmarks" % count.intToStr
  result = html(
    head(bootstrap_import),
    `div`(class = "ui container",
      h2(title, class="navbar"),
      `div`(class = "ui relaxed divided items",
        bookmarks_result.join("\n")
      )
    )
    )
  # return $result

routes:
  get "/":

    resp get_bookmarks(bookmarks_table)
  get "/style.css":
    resp style_css
  get "/q=@search_str":
    var search_str = @"search_str"
    resp get_bookmarks(bookmarks_table, search_str=search_str)
  get "/t=@tag":
    var tag = @"tag"
    resp get_bookmarks(bookmarks_table, tag=tag.decodeUrl)
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

  get "/delete":
    var
      args = initTable[string, string]()
      operation = "Delete a bookMark"
      url = decodeUrl request.params["url"]

    args["url"] = url
    for i in "name note tags".split(" "):
      args[i] = decodeUrl request.params.getOrDefault(i, "")

    if args["url"] in bookmarks_table:
      args["name"] = bookmarks_table[url].name
      args["note"] = bookmarks_table[url].note
      args["tags"] = bookmarks_table[url].tags

    var user_input = ""
    for i in "url note tags".split(" "):
      var tmp_input: string
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
              item_desc_template % [user_input, operation, "/delete"]
              )

  post "/delete":
    var
      url = @"url"

    if url in bookmarks_table:
      echo "Delete a bookmark:$1 $2" % [url, $bookmarks_table[url]]
      bookmarks_table.del(url)
      echo "Dump full by Delete API"
      dump_table(bookmarks_file_name, bookmarks_table)
    else:
      echo "URL:$1 not in bookmarks" % url

    resp html(
      h1("Delete Success"),
      h1("url:",
      a(href=url, url)
      )
      )
  get "/a":
    var
      args = initTable[string, string]()
      operation = "Add BookMark"
      url = decodeUrl request.params["url"]

    args["url"] = url
    for i in "name note tags".split(" "):
      args[i] = decodeUrl request.params.getOrDefault(i, "")

    if args["url"] in bookmarks_table:
      args["name"] = bookmarks_table[url].name
      args["note"] = bookmarks_table[url].note
      args["tags"] = bookmarks_table[url].tags
      operation = "Update BookMark"

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
              item_desc_template % [user_input, operation, "/"]
              )
