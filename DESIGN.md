---
name: MoonBit Android Sparse
description: 用于精确检查本地稀疏镜像的石墨色工作区。
colors:
  workspace: "#171b20"
  surface: "#1d2229"
  ink: "#e5e9ed"
  muted: "#a5afb9"
  accent: "#a4d7d2"
  rule: "#343d47"
  subtle: "#242c34"
  fill: "#8eabc2"
  skip: "#9aa5b0"
  crc: "#e8c48d"
  error: "#efb0a5"
typography:
  headline:
    fontFamily: '"Segoe UI", system-ui, -apple-system, BlinkMacSystemFont, sans-serif'
    fontSize: "25px"
    fontWeight: 600
    lineHeight: 1.25
    letterSpacing: "-0.025em"
  title:
    fontFamily: '"Segoe UI", system-ui, -apple-system, BlinkMacSystemFont, sans-serif'
    fontSize: "16px"
    fontWeight: 600
    letterSpacing: "-0.01em"
  body:
    fontFamily: '"Segoe UI", system-ui, -apple-system, BlinkMacSystemFont, sans-serif'
    fontSize: "14px"
    fontWeight: 400
  control:
    fontFamily: '"Segoe UI", system-ui, -apple-system, BlinkMacSystemFont, sans-serif'
    fontSize: "13px"
    fontWeight: 500
  label:
    fontFamily: '"Segoe UI", system-ui, -apple-system, BlinkMacSystemFont, sans-serif'
    fontSize: "11px"
    fontWeight: 400
  data:
    fontFamily: '"Cascadia Code", "Consolas", "SFMono-Regular", monospace'
    fontSize: "12px"
    fontWeight: 400
rounded:
  control: "5px"
  field: "4px"
  tag: "3px"
spacing:
  compact: "8px"
  tight: "12px"
  standard: "16px"
  gutter: "20px"
  section: "24px"
  workspace: "40px"
  wide: "64px"
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "#142626"
    typography: "{typography.control}"
    rounded: "{rounded.control}"
    padding: "0 14px"
  button-primary-hover:
    backgroundColor: "#bee5e1"
  button-primary-active:
    backgroundColor: "#8abeb9"
  button-secondary:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    typography: "{typography.control}"
    rounded: "{rounded.control}"
    padding: "0 14px"
  button-small:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "0 10px"
  button-text:
    backgroundColor: "transparent"
    textColor: "{colors.accent}"
    padding: "3px 0"
  crc-checkbox:
    size: "15px"
  type-select:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.field}"
    padding: "0 24px 0 9px"
  synthetic-tag:
    backgroundColor: "transparent"
    textColor: "#c3cbd3"
    rounded: "{rounded.tag}"
    padding: "2px 5px"
  allocation-strip:
    backgroundColor: "#101419"
    padding: "3px"
  chunk-ledger:
    backgroundColor: "{colors.workspace}"
    textColor: "{colors.ink}"
  error-report:
    backgroundColor: "#2a2224"
    padding: "22px 24px"
---

# 设计系统：MoonBit Android Sparse

## 概览

**创意北极星：“存储分配账本”**

安静的石墨色工作画布通过对齐的测量值、细分隔线和少量语义颜色呈现二进制结构。系统界面字体承载控件与标签，等宽字体承载偏移量、大小和数量。整体紧凑、精确、克制。

可复用的标志性模式是与密集账本联动的比例分配条。空洞使用轮廓，始终与存储数据保持可见区别。状态始终具有文字标签，尤其区分结构有效与 CRC 校验通过。功能性的留白和平面表面让注意力停留在待检查镜像上。

本规范提取自当前的 `inspector/src/App.tsx` 与 `inspector/src/styles.css`，并与已有桌面及移动端截图核对。前置元数据记录已实现的令牌，侧车文件补充组件示例与元数据。示例展示外观与状态，不实现检查流程。

**关键特征：**

- 石墨色色阶与精细账本分隔线。
- 等宽、表格数字与朴素系统界面标签并用。
- 具有语义的块颜色和空心 Skip 表示。
- 紧凑控件、可见键盘焦点和克制的状态过渡。

## 颜色

柔和的青色、板岩色与琥珀色在冷石墨色中传递含义；前置元数据是颜色的规范来源。

### 主色

- **计量青**（`accent`）：文件选择操作、RAW 数据、结构完成状态、已验证 CRC 和键盘焦点。

### 辅助色

- **存储板岩色**（`fill`）：FILL 分段及其类型标签。
- **校验琥珀色**（`crc`）：CRC32 分段、未经验证的 CRC 状态，以及读取和取消状态。
- **失败陶土色**（`error`）：检查失败标题和停止状态。

### 中性色

- **工作区石墨色**（`workspace`）与**账本石墨色**（`surface`）：主画布及测量或控件表面。
- **阅读墨色**（`ink`）与**静钢色**（`muted`）：主要内容与辅助标签。
- **账本分隔色**（`rule`）与**凹槽石墨色**（`subtle`）：边界和进度轨道。
- **空洞轮廓色**（`skip`）：Skip 分段的无填充边界。表格类型标签使用局部的较亮中性色以便阅读。

**语义颜色规则。** 保持 RAW、FILL、Skip 与 CRC32 的视觉区别，并为每种颜色配备标签或无障碍名称。

## 字体

**标题与正文字体：** Segoe UI，回退到系统界面字体和无衬线字体。

**数据字体：** Cascadia Code，回退到 Consolas、SFMono-Regular 和等宽字体。

**特征：** 熟悉的界面字体提供中性的阅读表面。等宽表格数字稳定呈现列间对比和十六进制偏移量；不采用展示性字体处理。

### 层级

- **主标题：** 单一工作标题使用 `headline`；在移动断点缩小为紧凑字号（22px）。
- **章节标题：** 使用 `title`；移动端缩小为紧凑字号（15px）。
- **正文：** 根节点使用 `body`。错误说明使用便于阅读的行高（1.6）与受限行宽（75ch）。
- **控件与标签：** `control` 用于标准按钮；`label` 用于定义标签与辅助元数据。表头、版本文字和移动端元数据使用局部的更小字号。
- **数据：** `data` 用于表格测量值，并采用表格数字。头部数值稍大（13px），移动端变为紧凑字号（12px）。

**测量规则。** 偏移量、字节大小、块数和分页数量使用等宽表格数字；说明文字与控件保持系统界面字体。

## 布局

画布居中且有宽度上限（1680px）。标准工作区横向边距使用 `spacing.workspace`；宽屏（最小宽度 1500px）使用 `spacing.wide`。移动端（最大宽度 640px）使用 `spacing.gutter`，允许控件、文件摘要和页脚换行。页面支持最小视口宽度（320px）。

当前检查器依次呈现文件控件、文件摘要、头部测量值、分配条和块账本。这是当前表面的实际构成，不是所有未来页面必须采用的模板。应复用其对齐、紧凑间距和以分隔线组织信息的方式。

头部测量账本在中间断点（最大宽度 1100px）由六列变为三列，移动端再变为两列。分配图例在移动端也变为两列。块表格在可聚焦的横向滚动区域中保留列结构和最小宽度（700px），避免将偏移量挤入窄单元格。表格正文行保持一致高度（46px），表头较矮（38px）。

## 层次与深度

不使用阴影。层次通过色阶、单像素分隔线、轮廓控件和选中行的柔和青色表面体现。较暗的分配凹槽承载分段。拖入反馈使用位于工作区内部的半透明虚线覆盖层，不引入悬浮面板体系。

**平面表面规则。** 使用色调区分与分隔线建立分组，保留已实现的无阴影层次模型。

## 形状

控件采用小而明确的圆角：按钮使用 `rounded.control`，选择框和跳转链接使用 `rounded.field`，合成数据标签使用 `rounded.tag`。测量账本、表格行、分配轨道和错误报告保持直角。细描边定义边界。小型圆形本地文件指示点是状态标记，不是通用容器形状。

## 组件

### 按钮

紧凑且实用。标准按钮具有适中的最小高度（40px）、单像素边界和可选的内联描边图标。主要操作采用计量青与深色文字，次要操作采用透明背景和账本分隔色轮廓。悬停改变背景和边框，按下再次改变背景。报告与分页的紧凑操作具有较小的最小高度（32px）和较小字号（12px）。禁用按钮降低不透明度（0.45），并显示禁止操作光标。

文字操作使用青色和下划线，不设容器。悬停时文字变亮，下划线加深。所有按钮保留统一的可见键盘轮廓（2px，外偏移 4px）。

### 输入与字段

文件输入保持原生，隐藏在文件选择按钮之后。CRC 校验使用带标签的原生复选框，方形控件紧凑（15px），采用青色强调与统一焦点轮廓；读取期间禁用。类型筛选使用原生选择框，搭配深色表面、细边框和 `rounded.field`。弹出菜单和指针行为保留平台原生表现，没有自定义悬停颜色覆盖。

### 标签与状态

小型轮廓 Synthetic 标签标识生成的数据，不具备交互。状态文字区分读取、完成、取消和失败。CRC 文字在验证通过前独立使用琥珀色，验证通过后使用青色。结构有效不得在视觉上暗示校验和已通过。进度条是细青色条（4px），没有宽度过渡。

### 测量与块账本

定义单元格共用一个带内部细线的深色表面。块账本采用有分隔线的表格、柔和表头、等宽数值和右对齐数字列。悬停轻微提亮行色。选中时增加柔和青色行背景与青色行选择器；每个选择器都是真实按钮，带有 `aria-pressed`。表格滚动区域可由键盘聚焦。筛选会重置分页，每页最多 100 条记录。当前没有独立卡片或应用导航组件。

### 分配条

相邻的平面分段按钮按逻辑块数确定比例。RAW 为青色，FILL 为板岩色，Skip 为透明背景加中性轮廓，CRC32 为琥珀色。零输出分段保留小型标记基础宽度（4px）。块数超过 240 时，将相邻块组成分段；混合组使用局部中性填充。选择分段会清除类型筛选、打开对应账本页、选中首个块并将行滚动到可见区域，不会将键盘焦点移到该行。选中分段增加内嵌亮色轮廓；悬停、选中和键盘聚焦时恢复完全不透明。

### 失败与拖入反馈

失败报告采用陶土色调的深色表面、柔和红色细边界、可读消息、输入偏移量和文件选择操作。拖入文件时显示青色虚线工作区覆盖层。空白与取消状态仅保留相关文件操作及功能性状态文字。

状态动画仅用于按钮背景或边框变化以及分段不透明度（180ms，`cubic-bezier(0.16, 1, 0.3, 1)`）。减少动态效果偏好会移除过渡。定位账本行时立即滚动。

## 应做与不应做

### 应做：

- **应**保持测量值等宽、采用表格数字并对齐。
- **应**保留空心 Skip 表示和明确的块标签。
- **应**分别呈现结构与 CRC 状态。
- **应**保留可见键盘焦点及窄屏横向表格访问。
- **应**使用紧凑分隔线和色阶组织工作信息。

### 不应做：

- **不应**将 Skip 空洞着色为存储的零数据。
- **不应**为未检查或不存在的 CRC 使用已验证样式。
- **不应**向当前平面组件体系增加阴影。
- **不应**使用营销或建议面板替换功能性空白画布。
- **不应**将本检查器的章节顺序推广为通用页面模板。
