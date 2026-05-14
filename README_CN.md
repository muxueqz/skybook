# skybook
[![Build Status](https://travis-ci.org/muxueqz/skybook.svg?branch=master)](https://travis-ci.org/muxueqz/skybook)

轻量级自托管书签管理器（Delicious 替代品）

## 截图
![](./add_bookmark.jpg)
![](./screenshot.jpg)

## 特性
- **搜索**：内建搜索栏或浏览器自定义搜索引擎，即时检索
- **JSON 存储**：每条书签存为一行 JSON，天然支持 git 版本管理
- **纯本地运行**：无网络依赖，无第三方服务关停风险
- **书签小工具**：浏览器书签栏一键添加当前页面
- **标签管理**：自动补全提示、多标签 AND 组合筛选
- **分页加载**：渐进加载，大数据量下性能友好

## 技术栈
- 后端：Nim + `asynchttpserver`
- 前端：Nim + [Karax](https://github.com/karaxnim/karax)（SPA 框架，编译为 JS）
- 存储：纯文本 JSON 文件（`bookmarks.db`）

## 前提条件
- Nim >= 2.0.0（推荐通过 [choosenim](https://nim-lang.org/install.html) 安装）

## 安装

### 通过 Nimble
```bash
nimble install skybook
```

### 手动编译
```bash
nim c --threadAnalysis:off -o:skybook src/skybook.nim
nim js --hint[Path]:off -o:src/frontend/app.js src/frontend/app.nim
./skybook
```

或使用构建脚本：
```bash
./build.sh
```

## 使用

启动服务后访问 `http://127.0.0.1:5000/`：
```bash
skybook
```

### 添加书签
- 点击页面上方 **Add** 按钮，填写 URL、名称、标签、备注后保存
- 或使用书签小工具（见下方）从任意网页自动填充

### 安装书签小工具
打开 Skybook 页面，将以下链接拖拽到浏览器书签栏：

<a href="javascript:(function(){var title=encodeURIComponent(document.title);var url=encodeURIComponent(location.href);var note='';var description=document.getElementsByName('description')[0];if(description){note=encodeURIComponent(description.content);}window.open('http://localhost:5000/a?name='+title+'&note='+note+'&url='+url);}).call(this);">📎 添加到 Skybook</a>

点击该书签即可将当前页面添加到 Skybook。

### 配置浏览器自定义搜索引擎
搜索网址设为 `http://localhost:5000/a?q=%s`，可在地址栏快速搜索书签。

### 管理书签
- 搜索框实时检索（匹配名称、备注、标签）
- 点击标签筛选，多标签用 AND 逻辑组合
- 支持编辑、删除、批量删除

## 配置

命令行参数：

| 参数 | 简写 | 默认值 | 示例 |
|------|------|--------|------|
| `--port` | `-p` | 5000 | `skybook -p 8080` |
| `--address` | `-a` | 127.0.0.1 | `skybook -a 0.0.0.0` |
| `--db` | `-d` | bookmarks.db | `skybook -d ~/bookmarks.db` |

## 许可证
GPL-2.0
