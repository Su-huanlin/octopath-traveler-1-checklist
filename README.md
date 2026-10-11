# 八方旅人 1 · 便携收集检查器

一个**纯前端**的 Steam《OCTOPATH TRAVELER / 八方旅人》收集进度工具：打开单个 HTML，本地选择（或加载示例）`.sav`，即可对照四大收集向成就查漏补缺。

| 成就 | 本工具对应页签 | 数量 |
|------|----------------|------|
| 宝箱猎人 | 宝箱 | 734 |
| 滴水不漏的旅行者 | 隐藏道具 | 152 |
| 战略家 | 怪物弱点 | 381 |
| 收藏家 | 道具 / 装备 / 贵重 / 情报 | 640 |

**特点：** 存档只在浏览器里解析，不上传服务器；中文地名与官方文本对齐；剧情可错过项单独标注；找法尽量写到「城镇 + 人物 + 方法」。

---

## 为什么要做这个工具

全收集不是「看一眼攻略就能勾完」的事：

- 可错过宝箱 / 隐藏道具 / 限时 NPC / 危险度上升后消失的怪物，散落在八大地区与各章剧情里。
- 收藏家清单长达 640 项，情报、面具、序章限定道具等很容易和「普通商店货」混在一起。
- 现有社区资源（Excel 总表、存档编辑器、Steam 攻略）各自很强，但缺少一个**对着自己存档实时标红「还差什么」**的中文界面。

于是做了这个**单文件便携检查器**：数据来自游戏解包与社区清单，进度来自你自己的 `SaveData*.sav`，打开就能用。

---

## 快速使用

### 方式 A：直接打开（最简单）

1. 打开 [`OctopathTrackerOutput/octopath_tracker_portable.html`](OctopathTrackerOutput/octopath_tracker_portable.html)
2. 选择本机存档，或点 **「加载示例存档」**（见下方说明）
3. 用「类型 / 状态」筛选，按地区折叠查看未完成项

存档常见路径（Windows）：

```text
%USERPROFILE%\Documents\My Games\Octopath_Traveler\<Steam数字ID>\SaveGames\SaveData1.sav
```

若开了 OneDrive 文档同步，可能在 `OneDrive\文档\My Games\Octopath_Traveler\...`。

### 方式 B：本地 HTTP（推荐，示例存档一键可点）

浏览器对 `file://` 常禁止 `fetch`，示例存档按钮可能失效。在仓库根目录执行：

```bash
# Python 3
python -m http.server 8080
```

浏览器打开：

```text
http://localhost:8080/OctopathTrackerOutput/octopath_tracker_portable.html
```

再点 **加载示例存档**。

### 示例存档

仓库内附带作者手动存档第 1 槽副本：

- [`samples/SaveData1.sav`](samples/SaveData1.sav)
- 生成时会同步到 `OctopathTrackerOutput/samples/SaveData1.sav`

仅供演示进度解析与界面效果；**请勿覆盖你自己的游戏存档**。其中包含个人游玩进度，上传公开仓库前请自行确认是否接受。

### 重新生成 HTML（开发者）

需要本机已有游戏 Content 解包数据与 Python（用于收藏家找法重建）时：

```bat
generate_portable_tracker.cmd
```

或：

```bat
rebuild_all.cmd
```

---

## 这是 Web App 吗？要不要上 Vercel？

**算。** 更准确地说：这是**静态、纯客户端的 Web App**（单页 HTML + 可选示例 `.sav`），没有后端、没有账号、没有把存档传到服务器。

| 方案 | 建议 |
|------|------|
| **本地双击 HTML** | 自己用够了；示例按钮在部分浏览器下可能失败，可手动选 `samples/SaveData1.sav` |
| **GitHub Pages** | 仓库已在 GitHub 时最省事：静态托管同源 `html` + `samples/`，示例按钮可用 |
| **Vercel** | 同样可行；仓库根目录已放 [`vercel.json`](vercel.json)，根路径会跳到检查器页面 |

**结论：** 想分享给朋友一键打开 → Pages 或 Vercel 任一即可。部署后「加载示例存档」可正常工作（同源 `fetch`）。

### 部署到 Vercel（推荐步骤）

仓库地址：<https://github.com/Su-huanlin/octopath-traveler-tracker>

1. 打开 [vercel.com/new](https://vercel.com/new) ，用 **GitHub** 登录并授权访问该仓库。
2. **Import** `Su-huanlin/octopath-traveler-tracker`。
3. 设置建议：
   - **Framework Preset**: Other
   - **Build Command**: 留空
   - **Output Directory**: 留空
   - **Install Command**: 留空  
   Root Directory 保持默认（仓库根，含 `vercel.json`）。
4. 点 **Deploy**。约一分钟后得到 `*.vercel.app` 域名；打开首页即检查器。
5. 在页面上点 **加载示例存档** 验证；也可自己选本机 `.sav`。

之后每次 `git push` 到 `main`，Vercel 会自动重新部署。

用 CLI 时（可选，需本机已装 Node.js）：

```bash
npm i -g vercel
cd /path/to/octopath-traveler-tracker
vercel login
vercel --prod
```

---

## 我们如何「历经万难」做完（问题与解法）

下面按真实踩坑顺序，浓缩研发过程。

### 1. 城镇归类与「最近城镇」全错

**现象：** 幻影之森、伊冯老家地下等显示成错误城镇（例如应属斯托冈德一带却归到别处）。

**原因：** 误用 WorldMap 坐标 / 章节数字 → S/M/L 城的机械规则；城镇 key 与中文名也曾对反。

**解法：** 废弃不可靠的「章节数字映射」；以游戏文本表、手动 override、以及更贴近游玩路径的邻近规则重建；用 `town_check` / audit 导出反复对表。

### 2. 宝箱九宫格方位不准

**现象：** 山贼大本营等「左上 / 右下」和玩家体感相反。

**原因：** X 轴被错误翻转；边界框混入剧情临时候补 NPC，把地图包围盒拉歪。

**解法：** 迷宫相对存档水晶算方位；野外/城镇不翻转 X；边界只统计宝箱、隐藏点、存档点与常驻 NPC。

### 3. 战略家「已识破」数量离谱（甚至全 0）

**现象：** 从「偏少」到回归后「全部未遭遇」。

**原因：** 对整份约 2MB 存档反复扫 `IsAnalyse_` 时聚类错误；一度改成解析 `SaveEnemyData` ArrayProperty，却与本机存档布局不兼容。

**解法：** 对齐 [LoneWindG/OctopathTraveler-SaveDataEditor](https://github.com/LoneWindG/OctopathTraveler-SaveDataEditor) 的思路：全文件聚类 `IsAnalyse_`，用 `WeaknessOpen` 字节掩码判断是否识破全部弱点；清单以编辑器 / 社区的 **381** 只为准，不混一般 Boss 召唤物。

### 4. 收藏家整页 640/0 或「情报全是未得」

**现象：** 旗帜解析失败，或装备显示正常、情报却全未勾。

**原因：**

- 游戏里 `ItemFlag` 是一整段 Int 数组，不是独立的 `ItemFlag_0` 属性名。
- 情报（知识）**多数不会写进 ItemFlag**，而是留在背包/手册的 `ItemID_*` 槽位里。

**解法：** 同时读取 `ItemFlag` 位图 **与** 当前 `ItemID` 持有；高位道具 ID 的数组长度限制也一并放宽。判定「收藏家」时：曾拿过（旗帜）或仍在栏内（ItemID）都算已得（卖掉一般仍留旗帜；情报则以栏内为准）。

### 5. 找法文案「人类不可读」

**现象：** `贵族面具(325=326=327)`、把支线 NPC「罪人凯文」误当成地点、`Guard` 译成「警卫」而游戏里是「卫兵」、鱼贩支线后消失却仍写死两个刷点等。

**解法：**

- 去掉 SaveDataEditor 清单里的内部别名括号。
- 修正 Excel NPC 表解析：空的 `X`/`None` 行不能覆盖当前城镇名。
- `Guard` → 官方中文「卫兵」；室内 `HouseInFlag` 标注「房中」。
- 剧情独有道具（小酒壶、面具、黑市清单等）写死 `collector_special_hints.json`。

### 6. 编码、路径与工程卫生

**现象：** CMD 下中文乱码；OneDrive「文档」路径；PowerShell 脚本塞中文易坏。

**解法：** 日志强制 UTF-8；帮助文案用 HTML 实体 / JSON 注入；解包树与探针脚本用 `.gitignore` 排除，GitHub 只留可运行产物与生成脚本。

---

## 致敬与参考

本工具站在社区前辈的肩膀上。下列资源在清单口径、可错过说明、存档格式理解上不可或缺——**致谢每一位作者与维护者**。

### 存档结构 / 编辑器

- **[LoneWindG / OctopathTraveler-SaveDataEditor](https://github.com/LoneWindG/OctopathTraveler-SaveDataEditor)**  
  存档 GVAS 解析、`ItemFlag` / 弱点 / `item_inventory` 清单口径的重要参考。感谢开源。

### 社区资源表

- **marcv666 — Octopath Traveler Resource（Excel）**  
  NPC 购买/偷取/打听/比试掉落、商店货架、支线奖励等「找法」的主要数据源。没有这份表，收藏家页签做不到现在这个粒度。

### Steam 攻略（可错过 / 全收集向）

- **中文可错过整理（Steam 指南）**  
  [八方旅人可错过收集相关整理](https://steamcommunity.com/sharedfiles/filedetails/?id=2795091350)  
  隐藏道具、战略家危险度怪、收藏家剧情限时等说明大量对照社区共识与本指南精神；工具内「不计入成就 / 剧情限时」标注亦受其讨论启发。

### 其他讨论与存档研究

- GBAtemp 等早期存档编辑讨论、Switch 存档工具作者（如 TreasureChests 相关工作）对「UE 存档里到底有什么」的探索。
- 所有在评论区用「我漏了还能不能解锁」实测反馈的玩家——你们让成就判定从「攻略猜测」变成「可核对的工程问题」。

> 本仓库**不包含**商业游戏本体与完整解包资源。请通过合法途径购买游戏；重新生成 HTML 时请使用你自己的解包数据。

若上述链接或署名有遗漏、过时，欢迎开 Issue 补上——致敬名单应越长越好。

---

## 仓库结构（精简）

```text
OctopathTrackerOutput/
  octopath_tracker_portable.html   # 可直接使用的检查器
  samples/SaveData1.sav            # 示例存档（生成时从 samples/ 复制）
samples/SaveData1.sav              # 示例存档源文件
generate_portable_tracker.ps1/.cmd # 生成入口
build_collector_items.py           # 收藏家找法
build_hidden_item_hints.py         # 隐藏道具找法
collector_*.json / hidden_item_hints.json / achievement_kind_notes.json
strategist_enemies_381.json
```

本地解包目录、SaveDataEditor 源码树、探针脚本输出等默认不进 Git（见 `.gitignore`）。

---

## 隐私与声明

- 解析完全在本地浏览器完成；部署到公网时也**不会**自动上传用户选择的存档。
- 示例存档为作者个人进度，公开仓库即等于公开该进度快照。
- 非官方粉丝工具，与 Square Enix / ACQUIRE 无隶属关系。《八方旅人》及相关商标归权利方所有。

---

## License

生成脚本与本仓库自有 JSON/HTML 以仓库内声明为准（若暂未附加许可证文件，默认保留所有权利，仅供学习与个人全收集使用）。第三方 Excel / 指南 / 编辑器版权归原作者；请遵守其各自许可与 Steam 指南分享条款。
