# 支持按 tag 过滤

## 后端改动 — `src/skybook.nim`

### `get_bookmarks` proc (第 31-54 行)

将 `tag` 参数改为支持逗号分隔多标签（AND 逻辑），同时 `q` 和 `tag` 可同时生效：

```nim
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
```

## 前端改动 — `src/frontend/app.nim`

### 1. 新增全局变量 `filterTags` (第 25 行后)

```nim
var filterTags: cstring = ""
```

### 2. `loadBookmarks` 增加 `tags` 参数 (第 39 行)

参数签名改为（加在末尾，不破坏现有调用）：

```nim
proc loadBookmarks(q: cstring = "", off: int = 0, lim: int = 20,
                   append: bool = false, tags: cstring = "")
```

在 `&q=` 之后追加 URL 参数：
```nim
if tags != nil and tags != "":
  url = url & "&tag=" & $encodeURIComponent(tags)
```

### 3. 所有 `loadBookmarks` 调用处传递 `filterTags`

| 行 | 原调用 | 新调用 |
|----|--------|--------|
| 87 `onSearchInput` | `loadBookmarks(n.value)` | `loadBookmarks(n.value, tags=filterTags)` |
| 100 `deleteBookmark` | `loadBookmarks(searchQuery)` | `loadBookmarks(searchQuery, tags=filterTags)` |
| 112 `deleteSelected` | `loadBookmarks(searchQuery)` | `loadBookmarks(searchQuery, tags=filterTags)` |
| 139 `addBookmark` | `loadBookmarks(searchQuery)` | `loadBookmarks(searchQuery, tags=filterTags)` |
| 160 `updateBookmark` | `loadBookmarks(searchQuery)` | `loadBookmarks(searchQuery, tags=filterTags)` |
| 91 `loadMore` | `loadBookmarks(searchQuery, offset, limitVal, append=true)` | `loadBookmarks(searchQuery, offset, limitVal, append=true, tags=filterTags)` |

### 4. 新增 tag 筛选函数 (在 `editBookmark` 附近)

```nim
proc toggleFilterTag(tag: string) =
  var currentTags = getTagList($filterTags)
  let idx = currentTags.find(tag)
  if idx >= 0: currentTags.delete(idx)
  else: currentTags.add(tag)
  filterTags = cstring(currentTags.join(","))
  offset = 0
  editingUrl = ""
  showAddForm = false
  loadBookmarks(searchQuery, tags=filterTags)

proc clearFilterTags(ev: Event; n: VNode) =
  filterTags = ""
  offset = 0
  loadBookmarks(searchQuery, tags=filterTags)
```

### 5. 新增 closure 辅助函数

```nim
proc filterTagCb(tag: string): proc(ev: Event; n: VNode) =
  result = proc(ev: Event; n: VNode) = toggleFilterTag(tag)
```

### 6. `createDom` UI 变更

**a) 在 toolbar 和 add-form 之间插入 filter-tags-bar**：
```nim
let activeFilterTagList = getTagList($filterTags)
if activeFilterTagList.len > 0:
  tdiv(class = "filter-tags-bar"):
    for t in activeFilterTagList:
      let tagCopy = t
      span(class = "filter-tag"):
        text tagCopy
        span(class = "filter-tag-remove",
          onclick = filterTagCb(tagCopy)):
          text "×"
    span(class = "filter-tag-clear",
      onclick = clearFilterTags):
      text "清除筛选"
```

**b) bookmark-tags 中的 `.tag` 改为可点击** (第 276-279 行)：
```nim
tdiv(class = "bookmark-tags"):
  for t in bmTags.split(","):
    if t.strip() != "":
      let tagStr = t.strip()
      span(class = "tag", onclick = filterTagCb(tagStr)):
        text tagStr
```

### 7. `initBookmarklet` 扩展解析 `q` 和 `tag` URL 参数

在 `case key` 中增加：
```nim
of "q":
  searchQuery = cstring(val)
  hasQuery = true
of "tag":
  filterTags = cstring(val)
  hasTag = true
```

末尾增加触发加载：
```nim
if hasQuery or hasTag:
  loadBookmarks(searchQuery, tags=filterTags)
```

## CSS 改动 — `src/frontend/style.css`

文件末尾追加：

```css
.tag {
  cursor: pointer;
}
.tag:hover {
  background: #44679f;
  color: #fff;
}
.filter-tags-bar {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  align-items: center;
  margin-bottom: 15px;
  padding: 8px 12px;
  background: #fff;
  border: 1px solid #44679f;
  border-radius: 4px;
}
.filter-tag {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  background: #44679f;
  color: white;
  padding: 3px 8px;
  border-radius: 3px;
  font-size: 12px;
  font-weight: 600;
}
.filter-tag-remove {
  cursor: pointer;
  font-size: 14px;
  line-height: 1;
  opacity: 0.8;
}
.filter-tag-remove:hover {
  opacity: 1;
}
.filter-tag-clear {
  margin-left: auto;
  font-size: 12px;
  color: #999;
  cursor: pointer;
}
.filter-tag-clear:hover {
  color: #44679f;
}
```

## 向后兼容性

| 场景 | 结果 |
|------|------|
| `?q=python` | ✅ 搜索 "python" |
| `?tag=python` | ✅ 按 tag 筛选 |
| `?tag=python,web` | 🆕 AND 筛选 |
| `?q=django&tag=python` | 🆕 联合筛选 |
| bookmarklet `?url=...&name=...` | ✅ 不变 |
| 前端搜索框输入 | ✅ 不变 |
