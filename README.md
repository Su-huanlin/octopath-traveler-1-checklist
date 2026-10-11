# 八方旅人 1 · 收集检查器

等等党大胜利！！！

还在玩八方旅人1的同学有福啦！！！

作者在完成steam全收集成就时，翻攻略翻到烦，有些还找不到，关键是不知道自己已经收集了哪些，没有收集哪些，游戏本身也没有系统记录；看了看其他大佬做的工具，基本都是从一开始就记录收集了哪些东西的日记本工具，对于作者这种直到通关才想收集成就的玩家来说，这种游戏伴随日记本的工具形式显然就不适用了，故而做了这个小工具：把 Steam 存档丢进去，看看宝箱、隐藏道具、怪物弱点、收藏家还差啥，非常方便。

> **在线演示：** _https://su-huanlin.github.io/octopath-traveler-1-checklist/_  


---

## 能干什么

- **四大成就对表**：宝箱猎人 / 滴水不漏的旅行者 / 战略家 / 收藏家  
- **读你自己的 `.sav`**：进度在浏览器里算，不上传到服务器  
- **可错过的会标出来**：剧情限时 NPC、危险度怪、面具二选一之类  
- **找法尽量写人话**：哪个镇、谁、买偷还是比试（房中也会注一下）  
- **附带示例存档**：点「加载示例存档」就能看效果（别拿它覆盖你正在玩的档）

---

## 怎么用

1. 打开本仓库的 [`index.html`](index.html)（或上面的在线链接）  
2. 选择存档，或点 **加载示例存档**  
3. 用类型 / 状态筛选，按地区往下翻未完成项  

存档一般在：

```text
文档\My Games\Octopath_Traveler\<Steam数字ID>\SaveGames\SaveData1.sav
```

OneDrive 同步文档的话，路径可能在 `OneDrive\文档\...`。

> 直接双击 HTML 时，「加载示例」有时会被浏览器拦住；用在线地址，或在本目录跑 `python -m http.server` 再打开即可。

---

## 截图

_<img width="2559" height="1215" alt="image" src="https://github.com/user-attachments/assets/ddf7c8c1-d940-47df-8350-659a86854630" />
_

---

## 技术栈（面试官扫一眼够了）

纯静态页：**HTML + CSS + Vanilla JS**，无构建、无框架。存档按游戏 GVAS 结构在前端解析。清单与找法来自游戏解包文本 + 社区资源表，再自己对了一遍中文名和坑点。

本地若要重新生成页面（需要本机解包数据）：

```bat
generate_portable_tracker.cmd
```

会写出 `index.html`。

---

## 感谢

没有社区前辈这个工具会难做很多，按姓氏不排序致谢：

- [LoneWindG / OctopathTraveler-SaveDataEditor](https://github.com/LoneWindG/OctopathTraveler-SaveDataEditor) — 存档字段与收藏家清单口径  
- **marcv666** 的 Octopath Traveler Resource（Excel）— NPC / 商店 / 支线找法  
- [Steam 可错过收集整理](https://steamcommunity.com/sharedfiles/filedetails/?id=2795091350) — 限时与可错过共识  

以及所有在评论区晒「漏了还能不能解锁」的旅人。

---

## 说明

非官方粉丝工具，和 SE / ACQUIRE 无关。请支持正版。示例存档是我自己的进度快照，公开仓库等于公开这份进度，介意的话可以删掉 `samples/` 再部署。
