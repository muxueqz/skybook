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

let bootstrap_import = """
<link rel="stylesheet" href="https://cdn.bootcss.com/bootstrap/4.0.0/css/bootstrap.min.css" integrity="sha384-Gn5384xqQ1aoWXA+058RXPxPg6fy4IWvTNh0E263XmFcJlSAwiGgFAW/dAiS6JXm" crossorigin="anonymous">
<script src="https://cdn.bootcss.com/jquery/3.2.1/jquery.slim.min.js" integrity="sha384-KJ3o2DKtIkvYIK3UENzmM7KCkRr/rE9/Qpg6aAZGJwFDMVNA/GpGFF93hXpG5KkN" crossorigin="anonymous"></script>
<script src="https://cdn.bootcss.com/popper.js/1.12.9/umd/popper.min.js" integrity="sha384-ApNbgh9B+Y1QKtv3Rn7W3mgPxhU9K/ScQsAP7hUibX39j7fakFPskvXusvfa0b4Q" crossorigin="anonymous"></script>
<script src="https://cdn.bootcss.com/bootstrap/4.0.0/js/bootstrap.min.js" integrity="sha384-JZR6Spejh4U02d8jOt6vLEHfe/JQGiRRSQQxSfFWpi1MquVdAyjUar5+76PVCmYl" crossorigin="anonymous"></script>

<style>
body {
  font-size: 1.3rem;
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
        <div class="media text-muted pt-3">
          <img data-src="holder.js/32x32?theme=thumb&amp;bg=007bff&amp;fg=007bff&amp;size=1" alt="32x32" class="mr-2 rounded" src="data:image/svg+xml;charset=UTF-8,%3Csvg%20width%3D%2232%22%20height%3D%2232%22%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20viewBox%3D%220%200%2032%2032%22%20preserveAspectRatio%3D%22none%22%3E%3Cdefs%3E%3Cstyle%20type%3D%22text%2Fcss%22%3E%23holder_168b749fa03%20text%20%7B%20fill%3A%23007bff%3Bfont-weight%3Abold%3Bfont-family%3AArial%2C%20Helvetica%2C%20Open%20Sans%2C%20sans-serif%2C%20monospace%3Bfont-size%3A2pt%20%7D%20%3C%2Fstyle%3E%3C%2Fdefs%3E%3Cg%20id%3D%22holder_168b749fa03%22%3E%3Crect%20width%3D%2232%22%20height%3D%2232%22%20fill%3D%22%23007bff%22%3E%3C%2Frect%3E%3Cg%3E%3Ctext%20x%3D%2212.046875%22%20y%3D%2217.2%22%3E32x32%3C%2Ftext%3E%3C%2Fg%3E%3C%2Fg%3E%3C%2Fsvg%3E" data-holder-rendered="true" style="width: 32px; height: 32px;">
          <div class="media-body pb-3 mb-0 lh-125 border-bottom border-gray">
            <div class="d-flex justify-content-between align-items-center w-100">
              <a href="$2">
                <strong class="text-gray-dark">$1</strong>
              </a>
              <a href="$3">Edit</a>
            </div>

      <svg aria-label="star" class="octicon octicon-star"
      viewBox="0 0 14 16" version="1.1" width="14" height="16" role="img">
      <path fill-rule="evenodd"
      d="M14 6l-4.9-.64L7 1 4.9 5.36 0 6l3.6 3.26L2.67 14 7 11.67 11.33 14l-.93-4.74L14 6z">
      </path></svg>
            <span class="d-bloak badge">Tags: </span>
            <span class="d-bloak">$4</span>
            <BR>
            <span class="d-bloak badge">Note: </span>
            <BR>
            <span class="d-bloak">$5</span>
          </div>
        </div>
"""

routes:
  get "/":
    var bookmarks_result: seq[string]

    for v in bookmarks_table.values():
      var
        url = v.url
        name = v.name
        edit_url = "http://localhost:5000/a?url=" & encodeUrl(url)
      bookmarks_result.add(item_template % [
        name, url, edit_url,
        v.tags,
        v.note.replace("\n", "<BR>")
        ])
      
    resp html(
      head(bootstrap_import),
      `div`(class = "container center-block",
        h3("BookMarks:"),
        bookmarks_result.join("\n")
      )
      )
  get "/q=@search_str":
    var bookmarks_result: seq[string]

    var search_str = @"search_str"
    for v in bookmarks_table.values():
      var
        url = v.url
        name = v.name
        edit_url = "http://localhost:5000/a?url=" & encodeUrl(url)
      if search_str in name:
        bookmarks_result.add(item_template % [
          name, url, edit_url,
          v.tags,
          v.note.replace("\n", "<BR>")
          ])
      
    resp html(
      head(bootstrap_import),
      `div`(class = "container center-block",
        h3("BookMarks:"),
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
      name = decodeUrl request.params.getOrDefault("name", "")
      note = decodeUrl request.params.getOrDefault("note", "")

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
