# 大算机器人品牌识别指南

**DaSuan Robotics Brand Identity Guide**

版本：v1.0.0
日期：2026-04-03
适用范围：ORIX 教育版四足机器狗全线产品、SDK 文档、市场材料

---

## 目录

1. [品牌名称](#1-品牌名称)
2. [品牌定位](#2-品牌定位)
3. [Logo 概念方案](#3-logo-概念方案)
4. [色彩体系](#4-色彩体系)
5. [字体规范](#5-字体规范)
6. [SDK 文档中的品牌应用](#6-sdk-文档中的品牌应用)
7. [品牌语言风格](#7-品牌语言风格)

---

## 1. 品牌名称

### 中文名称

**大算机器人**

### 英文名称

**DaSuan Robotics**

### 产品名称

**ORIX 教育版四足机器狗**（ORIX Educational Quadruped Robot Dog）

### 名称释义

**"大算"** 兼具三层含义：

1. **大计算（Great Computation）**——机器人的核心是算力与算法。"大算"直指教育机器人背后的计算本质：强化学习训练、运动控制推理、传感器融合，每一步行走都是一次大规模计算的结果。
2. **大算盘（Grand Abacus）**——算盘是中国最早的计算工具，"大算"致敬中国计算传统，同时暗示我们正在用现代技术重新定义"计算"的边界。从算盘到四足机器人，计算的形式在变，求解问题的本质不变。
3. **大有算计（Well-Calculated）**——在教育领域，每一步都经过深思熟虑。我们不做玩具，做的是让学生真正理解机器人技术的教育工具。

**"ORIX"** 的命名逻辑：

- **O** — Open（开源开放的教育理念）
- **R** — Robotics（机器人技术）
- **I** — Intelligence（智能）
- **X** — eXploration（探索未知）

ORIX 同时谐音 "Oryx"（大羚羊），象征敏捷、优雅、在复杂地形中自如行走——恰如四足机器人的设计目标。

### 品牌层级

```
大算机器人（公司品牌）
  └── ORIX（产品品牌）
        └── ORIX 教育版四足机器狗（产品全称）
        └── ORIX Edu（产品简称，用于代码和 SDK）
```

### 使用规范

| 场景 | 正确用法 | 错误用法 |
|------|----------|----------|
| 正式文档首次出现 | 大算机器人（DaSuan Robotics） | 大算、dasuan、DASUAN |
| 正式文档后续引用 | 大算机器人 | 大算 Robotics |
| 产品首次出现 | ORIX 教育版四足机器狗 | orix 机器狗、Orix |
| 代码/SDK 中 | `orix`（全小写） | `ORIX`、`Orix`、`dasuan` |
| 英文语境 | DaSuan Robotics | Da Suan、DASUAN、Dasuan |

---

## 2. 品牌定位

### 一句话定位

> **专业级技术，教育级体验——让每一位学生都能触摸真实的机器人技术。**

### 核心理念

**"造中学，做中懂"**（Learn by Building, Understand by Doing）

我们相信：

- 机器人技术不应该被简化成"拼积木"——学生值得接触真正的工业级技术栈
- 但工业级技术也不应该让学生望而却步——好的教育产品应该降低门槛而不是降低天花板
- ORIX 的目标是：**让大学生用 3 行 Python 就能让机器狗站起来，同时保留深入到强化学习训练的完整路径**

### 目标用户

| 用户群体 | 核心需求 | ORIX 提供的价值 |
|----------|----------|-----------------|
| 高校机器人实验室 | 教学平台 + 科研工具 | 完整 SDK + 可二次开发的硬件 |
| STEM 教育机构 | 吸引学生的教学内容 | 即开即用 + 渐进式课程体系 |
| 机器人竞赛团队 | 竞赛用平台 | 高性能 + 开放接口 + 自定义策略 |
| 个人开发者/爱好者 | 学习四足机器人技术 | 详尽文档 + 活跃社区 |

### 竞争差异化

```
         专业度高
            |
    工业机器人  ----  ORIX（这里）
            |              |
            |          教育机器人（积木式）
            |
         专业度低
    ←—— 易用性低          易用性高 ——→
```

ORIX 占据的是 **右上象限**：既有工业级的技术深度（16 自由度、强化学习策略、CAN 总线通信），又有教育级的易用性（Python SDK、图形化调试、一键部署）。

### 品牌承诺

1. **真实技术栈**——不是玩具，是缩小版的工业四足机器人
2. **渐进式学习路径**——从 `orix.stand_up()` 到自己训练 RL 策略
3. **开源开放**——SDK 完全开源，硬件接口完全文档化
4. **中文优先**——所有文档、错误信息、社区讨论以中文为第一语言

---

## 3. Logo 概念方案

### 方案 A：几何科技风

**视觉元素：**

Logo 由四个相连的菱形构成一个抽象的四足动物剪影，线条采用等宽描边（2px），节点处用小圆点标记，形成类似电路板走线的视觉效果。四个菱形分别代表四条腿，中心的连接区域形成躯干。整体呈现水平对称结构。

"大算" 二字位于图形右侧，采用等宽无衬线字体，字间距略大于常规（tracking +50），营造技术感。"机器人" 三字以较小字号置于"大算"下方，形成品牌名的主副层级。

英文 "DaSuan Robotics" 以极细字重置于中文名称下方，作为辅助信息。

**字体选择：** 中文使用思源黑体 Bold，英文使用 Space Grotesk Medium。

**色彩：** 单色方案，主色为深青色（#0A6E78），线条与文字统一色调。

**适用场景：** 技术白皮书、API 文档封面、开发者大会。

**优势：** 科技感强，辨识度高，与"计算"主题契合。
**不足：** 对教育市场偏冷，缺乏亲和力。

---

### 方案 B：教育亲和风（推荐）

**视觉元素：**

Logo 以一只简化的四足机器狗侧面剪影为核心，线条圆润流畅，关节处用圆角矩形表示，整体姿态为自信站立、微微抬头的状态。机器狗的"眼睛"用一个实心圆点表示，略带俏皮感。

机器狗剪影的背部有一条微微上扬的弧线，暗示向上的学习曲线。尾巴末端自然延伸为一条弧线，收束于一个小圆点，仿佛画上了一个句号——象征"完整的学习闭环"。

"大算" 二字位于图形右侧或下方，采用思源黑体 Heavy 字重，笔画端点做微圆角处理（字体本身特性），兼顾专业与亲和。"ORIX" 以品牌主色的色块衬底反白显示，置于"大算机器人"旁侧或上方，形成产品标识。

整体构图紧凑，图形与文字的高度比约为 1:1，确保在小尺寸下（如 favicon、APP 图标）仍可识别。

**字体选择：** 中文使用思源黑体 Heavy（主标题）+ Regular（副标题），英文使用 Inter SemiBold。

**色彩：** 双色方案——机器狗剪影使用主品牌色青蓝（#0891B2），"ORIX" 色块使用活力橙（#F97316）作为点缀，"大算机器人" 文字使用深灰（#1E293B）。

**适用场景：** 产品包装、教材封面、官网、展会物料、SDK 文档。

**优势：** 亲和力强，教育市场接受度高，双色方案兼顾专业与活力，图形可独立使用。
**不足：** 科技感略弱于方案 A。

> **推荐理由：** 教育市场的核心购买决策者（高校教师、实验室主任）需要的是"专业但不吓人"的品牌形象。方案 B 的圆润线条传递"易于上手"的信号，同时保持了足够的专业度。双色方案让品牌在竞品中更具辨识度。

---

### 方案 C：工业极简风

**视觉元素：**

Logo 完全由文字构成，无独立图形元素。"DASUAN" 六个字母采用 Helvetica Neue Bold 排列，字母间距极度紧凑（tracking -30），形成一个视觉整体。字母 "A" 的横杠被替换为一条细线，微微倾斜，暗示机器人腿部的关节角度。

"大算机器人" 四个汉字以思源黑体 Light 字重置于英文下方，字间距大（tracking +100），与上方粗重的英文形成轻重对比。

整体只使用黑白两色，背景可以是白底黑字或黑底白字，不使用任何彩色。产品名 "ORIX" 在需要时以同样的字体风格单独出现，不附加任何图形修饰。

**字体选择：** 英文使用 Helvetica Neue Bold，中文使用思源黑体 Light。

**色彩：** 纯黑白方案。在必须使用彩色的场景中，仅使用单一的中性蓝（#475569）。

**适用场景：** 投资人 pitch deck、工程技术文档、合作伙伴协议。

**优势：** 极度克制，高级感强，在工程师群体中有天然好感。
**不足：** 在教育展会等需要吸引注意力的场景中缺乏存在感；纯文字 Logo 在小尺寸下辨识度不足。

---

### 最终推荐

**采用方案 B（教育亲和风）作为主 Logo 方案。**

在特定场景中可以切换：
- 技术文档内页：使用方案 B 的简化版（仅机器狗图形 + "ORIX"）
- 需要极度正式的场合：使用方案 C 的纯文字排版作为辅助方案

---

## 4. 色彩体系

### 主色（Primary）

品牌主色选用 **青蓝色（Cyan-Teal）**，兼具科技感与教育领域的信赖感。

| 名称 | 色值 | 用途 |
|------|------|------|
| **Teal 600（主色）** | `#0891B2` / RGB(8, 145, 178) | Logo、标题、主要按钮、链接 |
| Teal 700（深色变体） | `#0E7490` / RGB(14, 116, 144) | 悬停状态、深色背景上的主色 |
| Teal 500（浅色变体） | `#06B6D4` / RGB(6, 182, 212) | 浅色背景上的强调、图表高亮 |
| Teal 100（极浅底色） | `#CFFAFE` / RGB(207, 250, 254) | 信息提示框背景、代码块背景 |
| Teal 50（微底色） | `#ECFEFF` / RGB(236, 254, 255) | 卡片背景、表格隔行底色 |

### 强调色（Accent）

用于行动号召（CTA）、重要提示、交互元素高亮。

| 名称 | 色值 | 用途 |
|------|------|------|
| **Orange 500（强调色）** | `#F97316` / RGB(249, 115, 22) | CTA 按钮、重要标注、徽章 |
| Orange 600（深色变体） | `#EA580C` / RGB(234, 88, 12) | 悬停状态 |
| Orange 400（浅色变体） | `#FB923C` / RGB(251, 146, 60) | 浅色背景上的强调 |
| Orange 100（极浅底色） | `#FFEDD5` / RGB(255, 237, 213) | 警告提示框背景 |

### 功能色（Semantic）

| 名称 | 色值 | 用途 |
|------|------|------|
| 成功（Success） | `#16A34A` / RGB(22, 163, 74) | 成功状态、正确标记 |
| 警告（Warning） | `#EAB308` / RGB(234, 179, 8) | 注意事项、兼容性提示 |
| 错误（Error） | `#DC2626` / RGB(220, 38, 38) | 错误信息、危险操作 |
| 信息（Info） | `#2563EB` / RGB(37, 99, 235) | 提示信息、补充说明 |

### 中性色（Neutral）

| 名称 | 色值 | 用途 |
|------|------|------|
| **Slate 900（正文）** | `#0F172A` / RGB(15, 23, 42) | 正文文字 |
| Slate 700（次要文字） | `#334155` / RGB(51, 65, 85) | 副标题、图注 |
| Slate 500（辅助文字） | `#64748B` / RGB(100, 116, 139) | 占位符、禁用状态 |
| Slate 300（边框） | `#CBD5E1` / RGB(203, 213, 225) | 分割线、表格边框 |
| Slate 100（浅背景） | `#F1F5F9` / RGB(241, 245, 249) | 页面背景、代码块背景 |
| Slate 50（最浅背景） | `#F8FAFC` / RGB(248, 250, 252) | 卡片背景 |
| White | `#FFFFFF` / RGB(255, 255, 255) | 正文背景、按钮文字 |

### 深色模式（Dark Mode）

| 浅色模式 | 深色模式替代 | 说明 |
|----------|-------------|------|
| Slate 900 正文 | `#F1F5F9` Slate 100 | 文字反转 |
| White 背景 | `#0F172A` Slate 900 | 背景反转 |
| Slate 100 代码块背景 | `#1E293B` Slate 800 | 代码块背景 |
| Teal 600 主色 | `#22D3EE` Teal 400 | 深色背景上提高对比度 |
| Orange 500 强调色 | `#FB923C` Orange 400 | 深色背景上提高对比度 |
| Slate 300 边框 | `#475569` Slate 600 | 边框在深色背景上的适配 |

### LaTeX 色彩定义

```latex
% === 大算机器人品牌色 ===
% 主色
\definecolor{brand-primary}{HTML}{0891B2}
\definecolor{brand-primary-dark}{HTML}{0E7490}
\definecolor{brand-primary-light}{HTML}{06B6D4}
\definecolor{brand-primary-bg}{HTML}{ECFEFF}

% 强调色
\definecolor{brand-accent}{HTML}{F97316}
\definecolor{brand-accent-dark}{HTML}{EA580C}
\definecolor{brand-accent-light}{HTML}{FB923C}
\definecolor{brand-accent-bg}{HTML}{FFEDD5}

% 功能色
\definecolor{brand-success}{HTML}{16A34A}
\definecolor{brand-warning}{HTML}{EAB308}
\definecolor{brand-error}{HTML}{DC2626}
\definecolor{brand-info}{HTML}{2563EB}

% 中性色
\definecolor{brand-text}{HTML}{0F172A}
\definecolor{brand-text-secondary}{HTML}{334155}
\definecolor{brand-text-muted}{HTML}{64748B}
\definecolor{brand-border}{HTML}{CBD5E1}
\definecolor{brand-bg-subtle}{HTML}{F1F5F9}
\definecolor{brand-bg-card}{HTML}{F8FAFC}
```

---

## 5. 字体规范

### 中文字体

**首选：思源黑体（Source Han Sans SC）**

- 许可证：SIL Open Font License 1.1（可免费商用）
- 获取：[Google Fonts](https://fonts.google.com/specimen/Noto+Sans+SC) / [Adobe Fonts](https://fonts.adobe.com/fonts/source-han-sans-simplified-chinese)
- 选择理由：
  - 开源免费，无商业授权风险
  - 覆盖 GB 18030 全部中文字符
  - 7 个字重（ExtraLight 到 Black），满足全场景需求
  - 与英文 Inter 字体的 x-height 和笔画粗细匹配度极佳

**LaTeX 中使用：**

```latex
\setCJKmainfont{Source Han Sans SC}[
  UprightFont    = *-Regular,
  BoldFont       = *-Bold,
  ItalicFont     = *-Regular,        % 中文无斜体，使用正体替代
  BoldItalicFont = *-Bold,
]
% 备选（系统中未安装思源黑体时）
% \setCJKmainfont{Microsoft YaHei}
```

### 英文字体

**首选：Inter**

- 许可证：SIL Open Font License 1.1
- 获取：[Google Fonts](https://fonts.google.com/specimen/Inter)
- 选择理由：
  - 专为屏幕阅读设计，PDF 和网页上均表现优秀
  - 可变字体（Variable Font），一个文件覆盖所有字重
  - 内置编程友好特性（区分 0/O、1/l/I）
  - 在技术文档领域广泛采用（GitHub、Figma、Vercel）

**备选：Roboto**

当 Inter 不可用时使用 Roboto，两者的度量高度相似，可无缝替换。

**LaTeX 中使用：**

```latex
\setmainfont{Inter}[
  UprightFont    = *-Regular,
  BoldFont       = *-SemiBold,       % 技术文档用 SemiBold 而非 Bold，更克制
  ItalicFont     = *-Italic,
  BoldItalicFont = *-SemiBoldItalic,
]
```

### 代码字体

**首选：JetBrains Mono**

- 许可证：SIL Open Font License 1.1
- 获取：[JetBrains](https://www.jetbrains.com/mono/)
- 选择理由：
  - 专为代码阅读设计，等宽，连字支持
  - 字符区分度极高（0/O、1/l/I、`{}`/`()`）
  - 行高 1.2 时阅读最舒适

**LaTeX 中使用：**

```latex
\setmonofont{JetBrains Mono}[
  UprightFont    = *-Regular,
  BoldFont       = *-Bold,
  Scale          = 0.85,             % 等宽字体缩放 85%，与正文视觉等高
]
```

### 字号体系

| 层级 | 用途 | 字号（pt） | 字重 | 行高 | LaTeX 命令 |
|------|------|-----------|------|------|------------|
| H1 | 章标题 | 24 | Bold | 1.3 | `\chapter` |
| H2 | 节标题 | 18 | SemiBold | 1.3 | `\section` |
| H3 | 小节标题 | 14 | SemiBold | 1.4 | `\subsection` |
| H4 | 段落标题 | 12 | SemiBold | 1.4 | `\subsubsection` |
| Body | 正文 | 10.5 | Regular | 1.6 | 默认 |
| Caption | 图注/表注 | 9 | Regular | 1.4 | `\caption` |
| Code | 代码块 | 9 | Mono Regular | 1.3 | `\texttt` / `lstlisting` |
| Footnote | 脚注 | 8 | Regular | 1.4 | `\footnote` |

### 字号 LaTeX 配置

```latex
% 全局字号基准
\documentclass[10.5pt, a4paper]{ctexrep}

% 章节标题字号
\ctexset{
  chapter/format    = \huge\bfseries\color{brand-primary},   % 24pt
  section/format    = \Large\fontseries{sb}\selectfont,      % 18pt SemiBold
  subsection/format = \large\fontseries{sb}\selectfont,      % 14pt SemiBold
}

% 行距
\setlength{\parskip}{0.5\baselineskip}
\linespread{1.6}  % 正文行高
```

---

## 6. SDK 文档中的品牌应用

### PDF 手册封面布局

```
┌─────────────────────────────────────────────┐
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │                                     │    │
│  │     （品牌主色 #0891B2 色块区域）      │    │
│  │                                     │    │
│  │     [Logo 图形]                      │    │
│  │                                     │    │
│  │     ORIX 教育版四足机器狗              │    │  ← 白色，Inter SemiBold 28pt
│  │     SDK 开发手册                      │    │  ← 白色，思源黑体 Regular 20pt
│  │                                     │    │
│  │     v2.0                             │    │  ← 白色半透明，Inter Light 14pt
│  │                                     │    │
│  └─────────────────────────────────────┘    │
│                                             │
│                                             │
│  大算机器人                                  │  ← Slate 900, 思源黑体 Heavy 16pt
│  DaSuan Robotics                            │  ← Slate 500, Inter Regular 11pt
│                                             │
│  ──────────── ← 品牌主色细线                 │
│                                             │
│  Python SDK Reference Manual                │  ← Slate 700, Inter Medium 12pt
│  2026                                       │  ← Slate 500, Inter Light 12pt
│                                             │
└─────────────────────────────────────────────┘
```

**LaTeX 封面实现要点：**

```latex
\begin{titlepage}
  \begin{tikzpicture}[remember picture, overlay]
    % 上方品牌色块（覆盖页面上方 60%）
    \fill[brand-primary]
      (current page.north west) rectangle
      ([yshift=-0.6\paperheight]current page.north east);

    % 封面标题（白色文字在品牌色块上）
    \node[anchor=west, text=white, font=\fontsize{28}{36}\selectfont\bfseries]
      at ([xshift=3cm, yshift=-8cm]current page.north west)
      {ORIX 教育版四足机器狗};

    \node[anchor=west, text=white, font=\fontsize{20}{28}\selectfont]
      at ([xshift=3cm, yshift=-9.5cm]current page.north west)
      {SDK 开发手册};
  \end{tikzpicture}
\end{titlepage}
```

### 页眉页脚规范

**页眉（奇数页/章节起始页）：**

```
大算机器人 ORIX SDK                               第 3 章 运动控制
─────────────────────────────────────────────────────────────────
```

- 左侧："大算机器人 ORIX SDK"，思源黑体 Regular 8pt，色值 Slate 500
- 右侧：当前章节名，Inter Regular 8pt，色值 Slate 500
- 下划线：0.4pt，色值 Slate 300

**页脚：**

```
─────────────────────────────────────────────────────────────────
v2.0 | CC BY-NC-SA 4.0                                    - 42 -
```

- 左侧：版本号 + 许可证，Inter Light 8pt，色值 Slate 400
- 右侧：页码，Inter Medium 9pt，色值 Slate 700

### 代码注释中的品牌标识

```python
# ============================================================
#  ORIX SDK - 大算机器人 (DaSuan Robotics)
#  Copyright (c) 2026 DaSuan Robotics. All rights reserved.
# ============================================================

"""
ORIX 教育版四足机器狗 Python SDK

快速开始:
    from orix import Robot

    dog = Robot()
    dog.stand_up()
"""
```

### README 文件品牌标识

```markdown
# ORIX SDK

> 大算机器人 | DaSuan Robotics
> ORIX 教育版四足机器狗 Python SDK

---

[文档](https://docs.dasuan.com) |
[快速开始](./docs/01_快速开始.md) |
[API 参考](./docs/06_API参考.md)
```

### 代码示例的语法高亮配色

与品牌色系保持一致的代码高亮方案：

| 元素 | 色值 | 说明 |
|------|------|------|
| 关键字（def, class, if） | `#0891B2`（品牌主色） | 与品牌色统一 |
| 字符串 | `#16A34A`（Success 绿） | 清晰区分 |
| 数字/常量 | `#F97316`（品牌强调色） | 醒目突出 |
| 注释 | `#64748B`（Slate 500） | 低调不干扰 |
| 函数名 | `#2563EB`（Info 蓝） | 重要但不喧宾夺主 |
| 类名 | `#7C3AED`（紫色） | 独立于品牌色，避免混淆 |
| 普通文字 | `#0F172A`（Slate 900） | 正文色 |
| 背景 | `#F8FAFC`（Slate 50） | 极浅底色 |

**LaTeX lstlisting 配置：**

```latex
\lstdefinestyle{orix-python}{
  language         = Python,
  basicstyle       = \ttfamily\small\color{brand-text},
  keywordstyle     = \color{brand-primary}\bfseries,
  stringstyle      = \color{brand-success},
  commentstyle     = \color{brand-text-muted}\itshape,
  numberstyle      = \tiny\color{brand-text-muted},
  backgroundcolor  = \color{brand-bg-card},
  frame            = leftline,
  framerule        = 2pt,
  rulecolor        = \color{brand-primary},
  numbers          = left,
  numbersep        = 10pt,
  tabsize          = 4,
  breaklines       = true,
  showstringspaces = false,
  captionpos       = b,
}
\lstset{style=orix-python}
```

---

## 7. 品牌语言风格

### 基本原则

| 原则 | 说明 | 正面示例 | 反面示例 |
|------|------|----------|----------|
| 专业但平易 | 技术准确，表达清晰 | "IMU 传感器以 100Hz 频率采集姿态数据" | "超高精度传感器提供卓越的运动感知" |
| 解释原因 | 不只告诉 HOW，更要说 WHY | "使用 `await` 是因为站立动作需要约 2 秒完成" | "使用 `await` 关键字" |
| 中文优先 | 术语首次出现时中英对照 | "强化学习（Reinforcement Learning, RL）" | "RL policy training" |
| 无术语黑箱 | 每个术语第一次出现时解释 | "PD 控制器——一种根据当前误差和变化速率来调节输出的控制算法" | "PD 控制器负责关节力矩输出" |
| 鼓励探索 | 引导学生深入而非停留表面 | "试试修改 `kp` 参数，观察机器狗站立时的晃动变化" | "保持默认参数即可" |

### 文档层级的语气调整

| 文档类型 | 语气 | 示例 |
|----------|------|------|
| 快速开始 | 热情、鼓励 | "恭喜！你的机器狗已经站起来了。接下来我们让它走几步。" |
| API 参考 | 精确、克制 | "`stand_up(duration_s: float = 2.0)` — 从蹲伏状态过渡到站立。阻塞直到动作完成。" |
| 教程 | 循循善诱 | "你可能会好奇：为什么站立需要 2 秒？这是因为......" |
| 安全指南 | 严肃、明确 | "警告：绕过低压保护可能导致电机在无力矩状态下突然断电，机器狗将直接坍塌。" |
| 故障排查 | 冷静、系统化 | "如果机器狗无法站立，请按以下顺序检查：1. 电池电压 > 22V 2. CAN 总线连接......" |

### 特定措辞规范

| 场景 | 使用 | 避免 |
|------|------|------|
| 称呼用户 | "你" | "您"（SDK 文档场景偏技术，"你"更自然） |
| 称呼产品 | "ORIX" 或 "机器狗" | "本产品"、"该设备" |
| 表示建议 | "建议" / "推荐" | "必须"（除非真的是安全强制要求） |
| 表示安全要求 | "必须" / "禁止" | "建议"（安全事项不容商量） |
| 代码示例引导 | "试试这段代码" | "请执行以下代码" |
| 错误处理 | "遇到这个错误时" | "如果出现异常" |

### 品牌语言示例

**产品介绍页：**

> ORIX 是一台真正的四足机器人，不是玩具。
>
> 它搭载 16 个自由度的关节系统，运行基于强化学习训练的运动策略，通过 CAN 总线与每一个电机实时通信。这些技术与工业级四足机器人完全一致。
>
> 不同的是，我们为它配备了一套完整的 Python SDK。三行代码就能让它站起来，三十行代码就能让它按你设计的路线行走。而当你准备好了，还可以深入到 RL 策略训练、步态优化、传感器融合这些前沿课题。
>
> 学机器人，从让一只机器狗站起来开始。

**错误信息风格：**

```
[ORIX] 错误：无法连接到机器狗 (192.168.1.100:13145)

可能原因：
  1. 机器狗未开机或未完成启动（开机后需等待约 15 秒）
  2. 电脑与机器狗不在同一网段
  3. 防火墙阻止了 gRPC 端口

排查步骤：
  $ ping 192.168.1.100          # 检查网络连通性
  $ orix doctor                 # 运行自动诊断

如仍无法解决，请查看：docs/08_常见问题.md#连接问题
```

---

## 附录 A：品牌资产检查清单

在制作任何对外材料时，请对照以下清单：

- [ ] 品牌名称拼写正确（"大算机器人" / "DaSuan Robotics" / "ORIX"）
- [ ] 使用了正确的品牌色（主色 #0891B2，强调色 #F97316）
- [ ] 中文字体为思源黑体，英文字体为 Inter
- [ ] 代码示例使用 JetBrains Mono
- [ ] 首次出现的英文术语有中文翻译
- [ ] 安全相关内容使用"必须/禁止"而非"建议"
- [ ] 封面/页眉包含品牌标识
- [ ] 配色在深色/浅色背景下均有足够对比度（WCAG AA 标准）

## 附录 B：LaTeX 完整导言区模板

```latex
\documentclass[10.5pt, a4paper, openany]{ctexrep}

% ── 字体 ──
\usepackage{fontspec}
\setmainfont{Inter}[
  UprightFont    = *-Regular,
  BoldFont       = *-SemiBold,
  ItalicFont     = *-Italic,
  BoldItalicFont = *-SemiBoldItalic,
]
\setmonofont{JetBrains Mono}[
  UprightFont    = *-Regular,
  BoldFont       = *-Bold,
  Scale          = 0.85,
]
\setCJKmainfont{Source Han Sans SC}[
  UprightFont    = *-Regular,
  BoldFont       = *-Bold,
]

% ── 色彩 ──
\usepackage{xcolor}
\definecolor{brand-primary}{HTML}{0891B2}
\definecolor{brand-primary-dark}{HTML}{0E7490}
\definecolor{brand-primary-light}{HTML}{06B6D4}
\definecolor{brand-primary-bg}{HTML}{ECFEFF}
\definecolor{brand-accent}{HTML}{F97316}
\definecolor{brand-accent-dark}{HTML}{EA580C}
\definecolor{brand-accent-bg}{HTML}{FFEDD5}
\definecolor{brand-success}{HTML}{16A34A}
\definecolor{brand-warning}{HTML}{EAB308}
\definecolor{brand-error}{HTML}{DC2626}
\definecolor{brand-info}{HTML}{2563EB}
\definecolor{brand-text}{HTML}{0F172A}
\definecolor{brand-text-secondary}{HTML}{334155}
\definecolor{brand-text-muted}{HTML}{64748B}
\definecolor{brand-border}{HTML}{CBD5E1}
\definecolor{brand-bg-subtle}{HTML}{F1F5F9}
\definecolor{brand-bg-card}{HTML}{F8FAFC}

% ── 代码高亮 ──
\usepackage{listings}
\lstdefinestyle{orix-python}{
  language         = Python,
  basicstyle       = \ttfamily\small\color{brand-text},
  keywordstyle     = \color{brand-primary}\bfseries,
  stringstyle      = \color{brand-success},
  commentstyle     = \color{brand-text-muted}\itshape,
  numberstyle      = \tiny\color{brand-text-muted},
  backgroundcolor  = \color{brand-bg-card},
  frame            = leftline,
  framerule        = 2pt,
  rulecolor        = \color{brand-primary},
  numbers          = left,
  numbersep        = 10pt,
  tabsize          = 4,
  breaklines       = true,
  showstringspaces = false,
}
\lstset{style=orix-python}

% ── 章节样式 ──
\ctexset{
  chapter/format  = \huge\bfseries\color{brand-primary},
  section/format  = \Large\bfseries\color{brand-primary-dark},
  subsection/format = \large\bfseries,
}

% ── 页眉页脚 ──
\usepackage{fancyhdr}
\pagestyle{fancy}
\fancyhf{}
\fancyhead[L]{\small\color{brand-text-muted}大算机器人 ORIX SDK}
\fancyhead[R]{\small\color{brand-text-muted}\leftmark}
\fancyfoot[L]{\small\color{brand-text-muted}v2.0 | CC BY-NC-SA 4.0}
\fancyfoot[R]{\small\color{brand-text-secondary}\thepage}
\renewcommand{\headrulewidth}{0.4pt}
\renewcommand{\footrulewidth}{0.4pt}

% ── 超链接 ──
\usepackage{hyperref}
\hypersetup{
  colorlinks  = true,
  linkcolor   = brand-primary-dark,
  urlcolor    = brand-primary,
  citecolor   = brand-primary-dark,
}
```

---

*本品牌指南由大算机器人（DaSuan Robotics）制定，适用于 ORIX 教育版四足机器狗全线产品材料。*
*如有疑问，请联系品牌负责人。*
