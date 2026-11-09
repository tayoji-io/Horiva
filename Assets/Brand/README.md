# 时屿 · Horiva

**让每一刻，各在其时。**

## 名称

中文名“时屿”把不同时区比作时间海中的岛屿；英文名为 Horiva。功能说明使用副标题“多时区菜单栏时钟”。

## 图标

深蓝色圆角方形底，青蓝色钟环与暖金色日出交汇在地平线上。钟面指向时间显示；昼夜地平线表达世界各地的时间差异。图标不包含文字，可用于应用图标与品牌头像。

- `Horiva.png`：1254 × 1254 原始透明 PNG。
- `Horiva.icns`：macOS 多尺寸应用图标，包含 16–1024 像素资源。
- `scripts/build_icon.sh`：使用 macOS 原生 sips/iconutil 重新导出 ICNS。

图标仅用于应用包，不添加到每秒刷新的状态栏文字中。

## 生成与提示词

使用内置 imagegen 工具生成。原始生成文件保留在 Codex 生成目录，项目引用工作区内的 PNG。

完整提示词：

> Create one final production-quality macOS application icon for a small elegant world-time menu bar utility named Horiva, Chinese name 时屿 (time islands). Icon asset only, no words, no lettering, no numbers, no mockup, no presentation sheet. Square 1024 x 1024 composition. A native macOS rounded-square tile with a smooth very dark midnight-navy surface, occupying approximately 86% of canvas width, perfectly centered with equal transparent exterior margins. Outside the tile is genuinely transparent. Inside, create one unmistakable, extremely clean contemporary emblem: a luminous turquoise/aqua clock ring, intersected or gently split by a single graceful horizontal horizon arc. Two simple ivory clock hands visibly meet at the center, pointing roughly toward 10 and 2 o'clock. Let a small warm amber sun emerge on the upper right horizon, integrated into the emblem rather than a separate notification dot. Subtle warm-to-cool balance symbolizes different time zones sharing one instant. Restrained precision, bold simple silhouette legible at 32px, refined geometry, exceptionally balanced optical spacing, no busy globe grids, no tiny tick marks, no calendar, no airplane. Minimal and premium like a thoughtful native macOS utility, softly dimensional polished material with a very subtle internal glow, not glossy plastic, no excessive 3D bevels or dramatic cast shadows. The symbol must be large, centered, coherent and memorable. Keep the entire image as an icon with crisp edges. One icon only.
