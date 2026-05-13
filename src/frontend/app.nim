include karax / prelude
import karax / [kajax]
import json, strutils
import ../types

proc decodeURIComponent(s: cstring): cstring {.importc: "decodeURIComponent".}
proc encodeURIComponent(s: cstring): cstring {.importc: "encodeURIComponent".}
proc jsConfirm(msg: cstring): bool {.importc: "confirm".}

var locationSearch {.importc: "window.location.search".}: cstring

var
  bookmarks: seq[BookMark]
  searchQuery: cstring
  selectedUrls: seq[string]
  showAddForm: bool
  addUrl, addName, addNote: cstring
  editingUrl: string
  editName, editNote, editTags: cstring
  newTagInput: cstring
  offset: int
  limitVal = 20
  total: int
  pendingUrl, pendingName, pendingNote: string
  allTags: seq[string]

proc getTagList(tags: cstring): seq[string] =
  if tags == nil or $tags == "": return
  for t in ($tags).split(","):
    let trimmed = t.strip
    if trimmed != "": result.add(trimmed)

proc loadTags() =
  ajaxGet(cstring("/api/tags"), @[], proc (s: int; r: kstring) =
    if s == 200:
      allTags = parseJson($r).to(seq[string])
  )

proc loadBookmarks(q: cstring = "", off: int = 0, lim: int = 20, append: bool = false) =
  var url = "/api/bookmarks?offset=" & $off & "&limit=" & $lim
  if q != "":
    url = url & "&q=" & $encodeURIComponent(q)
  ajaxGet(cstring(url), @[], proc (s: int; r: kstring) =
    if s == 200:
      let resp = parseJson($r)
      total = resp["total"].num.int
      let items = resp["items"].to(seq[BookMark])
      if append:
        for item in items: bookmarks.add(item)
      else: bookmarks = items
      if pendingUrl != "":
        var found = false
        for bm in items:
          if bm.url == pendingUrl:
            editingUrl = pendingUrl
            editName = cstring(bm.name)
            editNote = cstring(bm.note)
            editTags = cstring(bm.tags)
            found = true
            break
        if not found:
          showAddForm = true
          addUrl = cstring(pendingUrl)
          addName = cstring(pendingName)
          addNote = cstring(pendingNote)
        pendingUrl = ""
  )

proc initBookmarklet() =
  let search = $locationSearch
  if search == "" or search[0] != '?': return
  for pair in search[1..^1].split("&"):
    let eqPos = pair.find("=")
    if eqPos < 0: continue
    let key = pair[0..<eqPos]
    let val = $decodeURIComponent(cstring(pair[eqPos+1..^1]))
    case key
    of "url": pendingUrl = val
    of "name": pendingName = val
    of "note": pendingNote = val

proc onSearchInput(ev: Event; n: VNode) =
  searchQuery = n.value
  offset = 0
  editingUrl = ""
  showAddForm = false
  loadBookmarks(n.value)

proc loadMore(ev: Event; n: VNode) =
  offset += limitVal
  loadBookmarks(searchQuery, offset, limitVal, append=true)

proc deleteBookmark(url: string) =
  if not jsConfirm(cstring("确定删除？")): return
  let data = $(%* {"url": url})
  ajaxPost(cstring("/api/bookmarks/delete"),
    @[("Content-Type".cstring, "application/json".cstring)],
    cstring(data),
    proc (s: int; r: kstring) =
      if s == 200: loadBookmarks(searchQuery))

proc deleteSelected(ev: Event; n: VNode) =
  if selectedUrls.len == 0: return
  if not jsConfirm(cstring("确定删除选中的 " & $selectedUrls.len & " 条书签？")): return
  let data = $(%* {"urls": selectedUrls})
  ajaxPost(cstring("/api/bookmarks/delete/batch"),
    @[("Content-Type".cstring, "application/json".cstring)],
    cstring(data),
    proc (s: int; r: kstring) =
      if s == 200:
        selectedUrls = @[]
        loadBookmarks(searchQuery))

proc toggleSelect(url: string) =
  let idx = selectedUrls.find(url)
  if idx >= 0: selectedUrls.delete(idx)
  else: selectedUrls.add(url)

proc addBookmark(ev: Event; n: VNode) =
  var tags = ""
  for t in getTagList(editTags):
    if tags != "": tags.add "," & t else: tags = t
  let data = $(%* {
    "url": $addUrl,
    "name": $addName,
    "note": $addNote,
    "tags": tags
  })
  ajaxPost(cstring("/api/bookmarks"),
    @[("Content-Type".cstring, "application/json".cstring)],
    cstring(data),
    proc (s: int; r: kstring) =
      if s == 200:
        showAddForm = false
        editingUrl = ""
        editTags = ""
        addUrl = ""; addName = ""; addNote = ""
        offset = 0
        loadBookmarks(searchQuery))
  loadTags()

proc updateBookmark(ev: Event; n: VNode) =
  var tags = ""
  for t in getTagList(editTags):
    if tags != "": tags.add "," & t else: tags = t
  let data = $(%* {
    "url": editingUrl,
    "name": $editName,
    "note": $editNote,
    "tags": tags
  })
  ajaxPost(cstring("/api/bookmarks"),
    @[("Content-Type".cstring, "application/json".cstring)],
    cstring(data),
    proc (s: int; r: kstring) =
      if s == 200:
        editingUrl = ""
        editName = ""; editNote = ""; editTags = ""
        offset = 0
        loadBookmarks(searchQuery))

proc cancelEdit() =
  editingUrl = ""
  editName = ""; editNote = ""; editTags = ""; newTagInput = ""
  addUrl = ""; addName = ""; addNote = ""

proc removeTag(tag: string) =
  var tags = getTagList(editTags)
  tags.delete(tags.find(tag))
  editTags = cstring(tags.join(","))

proc addTag() =
  let t = $newTagInput
  if t.strip() == "": return
  var tags = getTagList(editTags)
  tags.add(t.strip())
  editTags = cstring(tags.join(","))
  newTagInput = ""

proc addTagFromList(tag: string) =
  var tags = getTagList(editTags)
  if tag notin tags:
    tags.add(tag)
    editTags = cstring(tags.join(","))

proc editBookmark(url: string) =
  showAddForm = false
  addUrl = ""; addName = ""; addNote = ""
  for bm in bookmarks:
    if bm.url == url:
      editingUrl = url
      editName = cstring(bm.name)
      editNote = cstring(bm.note)
      editTags = cstring(bm.tags)
      newTagInput = ""
      break

# Helper functions to fix closure capture (each creates independent scope)
proc selectCb(url: string): proc(ev: Event; n: VNode) =
  result = proc(ev: Event; n: VNode) = toggleSelect(url)

proc editCb(url: string): proc(ev: Event; n: VNode) =
  result = proc(ev: Event; n: VNode) = editBookmark(url)

proc deleteCb(url: string): proc(ev: Event; n: VNode) =
  result = proc(ev: Event; n: VNode) = deleteBookmark(url)

proc tagSugCb(tag: string): proc(ev: Event; n: VNode) =
  result = proc(ev: Event; n: VNode) = addTagFromList(tag)

proc removeCb(tag: string, onRemove: proc(tag: string)): proc(ev: Event; n: VNode) =
  result = proc(ev: Event; n: VNode) = onRemove(tag)

proc renderTagChips(tags: cstring, onRemove: proc(tag: string)): VNode =
  let tagList = getTagList(tags)
  result = buildHtml(tdiv(class = "tag-chips")):
    for i in 0..<tagList.len:
      let tagCopy = tagList[i]
      span(class = "tag-chip"):
        text tagCopy
        span(class = "tag-remove",
          onclick = removeCb(tagCopy, onRemove)):
          text "×"

proc createDom(data: RouterData): VNode =
  result = buildHtml(tdiv(class = "app")):
    h1(class = "app-title"): text "Bookmarks"
    tdiv(class = "toolbar"):
      input(class = "search-input", placeholder = "Search...",
        value = searchQuery, oninput = onSearchInput)
      button(class = "add-btn", onclick = proc(ev: Event; n: VNode) =
        cancelEdit()
        showAddForm = not showAddForm
        if not showAddForm:
          addUrl = ""; addName = ""; addNote = ""):
        text if showAddForm: "Cancel" else: "Add"
    if showAddForm:
      tdiv(class = "add-form"):
        input(class = "form-input", placeholder = "URL", value = addUrl,
          oninput = proc(ev: Event; n: VNode) = addUrl = n.value)
        input(class = "form-input", placeholder = "Name", value = addName,
          oninput = proc(ev: Event; n: VNode) = addName = n.value)
        renderTagChips(editTags, removeTag)
        tdiv(class = "tag-add-row"):
          input(class = "tag-add-input", placeholder = "New tag...", value = newTagInput,
            oninput = proc(ev: Event; n: VNode) = newTagInput = n.value)
          button(class = "tag-add-btn", onclick = addTag): text "Add"
        let inp = $newTagInput
        if inp != "":
          tdiv(class = "tag-suggestions"):
            for t in allTags:
              if inp in t:
                let tagCopy = t
                span(class = "tag-suggestion",
                  onclick = tagSugCb(tagCopy)):
                  text tagCopy
        textarea(class = "form-input", placeholder = "Note", value = addNote,
          oninput = proc(ev: Event; n: VNode) = addNote = n.value)
        button(class = "save-btn", onclick = addBookmark): text "Save"
    tdiv(class = "bookmark-list"):
      for i in 0..<bookmarks.len:
        let bmUrl = bookmarks[i].url
        let bmName = bookmarks[i].name
        let bmNote = bookmarks[i].note
        let bmTags = bookmarks[i].tags
        let isEditing = bmUrl == editingUrl
        tdiv(class = cstring("bookmark-item" & (if isEditing: " editing" else: ""))):
          input(`type` = "checkbox",
            checked = toChecked(bmUrl in selectedUrls),
            onclick = selectCb(bmUrl))
          tdiv(class = "bookmark-body"):
            a(href = cstring(bmUrl), class = "bookmark-title"): text bmName
            tdiv(class = "bookmark-meta"): text cstring(bmUrl)
            if bmNote != "":
              tdiv(class = "bookmark-note"): text bmNote
            tdiv(class = "bookmark-tags"):
              for t in bmTags.split(","):
                if t.strip() != "":
                  span(class = "tag"): text t.strip()
          tdiv(class = "bookmark-actions"):
            button(class = "edit-btn",
              onclick = editCb(bmUrl)):
              text "Edit"
            button(class = "delete-btn",
              onclick = deleteCb(bmUrl)):
              text "Delete"
        if isEditing:
          tdiv(class = "inline-edit"):
            input(class = "form-input", placeholder = "Name", value = editName,
              oninput = proc(ev: Event; n: VNode) = editName = n.value)
            renderTagChips(editTags, removeTag)
            tdiv(class = "tag-add-row"):
              input(class = "tag-add-input", placeholder = "New tag...", value = newTagInput,
                oninput = proc(ev: Event; n: VNode) = newTagInput = n.value)
              button(class = "tag-add-btn", onclick = addTag): text "Add"
            let inp2 = $newTagInput
            if inp2 != "":
              tdiv(class = "tag-suggestions"):
                for t in allTags:
                  if inp2 in t:
                    let tagCopy = t
                    span(class = "tag-suggestion",
                      onclick = tagSugCb(tagCopy)):
                      text tagCopy
            textarea(class = "form-input", placeholder = "Note", value = editNote,
              oninput = proc(ev: Event; n: VNode) = editNote = n.value)
            tdiv(class = "inline-edit-actions"):
              button(class = "save-btn", onclick = updateBookmark): text "Update"
              button(class = "cancel-btn", onclick = proc(ev: Event; n: VNode) = cancelEdit()):
                text "Cancel"
    if total > offset + limitVal:
      tdiv(class = "load-more"):
        button(class = "load-more-btn", onclick = loadMore):
          text "Load More (" & cstring($(total - offset - limitVal)) & " remaining)"
    if selectedUrls.len > 0:
      tdiv(class = "batch-actions"):
        button(class = "delete-selected-btn", onclick = deleteSelected):
          text "Delete Selected (" & cstring($selectedUrls.len) & ")"

initBookmarklet()
setRenderer createDom
loadBookmarks()
loadTags()
