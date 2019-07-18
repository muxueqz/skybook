title = encodeURIComponent(document.title)
url = encodeURIComponent(location.href)
note = ''
description = document.getElementsByName('description')[0]
if description
  note = encodeURIComponent description.content
window.open 'http://localhost:5000/a?name=' + title + '&note=' + note + '&url=' + url
