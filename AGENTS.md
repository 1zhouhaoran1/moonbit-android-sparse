# 仓库贡献指南

## 沿镜像处理链定位代码

`kernel/` 负责纯 MoonBit sparse-v1 decoder、writer、CRC 和类型，测试与包同目录。`kernel/javascript/` 将事件适配给主机。`host/` 保存 Node CLI 和合成样本生成器；`inspector/` 保存 React/Vite/TypeScript/Tailwind worker 界面。`tooling/` 负责构建与检查；`reference/aosp/` 保存固定版本对照 harness。操作文档在 `handbook/`；`provenance/discovery/` 仅作为检索证据。

生成的桥文件和 `output/` 制品可重复生成，不将其作为源码编辑；个人资料和本地制品不得进入提交。

## 复现改动

- `pnpm install`：安装 workspace 依赖，只使用 pnpm。
- `pnpm build:codec`：MoonBit 改动后重新生成 JavaScript。
- `pnpm sample`：生成 `output/synthetic.sparse.img`；用 `pnpm cli inspect output/synthetic.sparse.img --json --crc` 检查。
- `pnpm dev`：在 `127.0.0.1:5178` 启动本地检查器；`pnpm build` 检查生产构建。
- `pnpm test`、`pnpm test:host`：验证核心后端和主机流程。

公共 API 改动后运行 `moon info`，审查生成的 `.mbti` 接口。

## 保留数据含义

解析逻辑与文件系统、浏览器 I/O 分离。只有显式空洞成为 DONT_CARE，字面零字节仍是数据；保留 `SkipData` 事件。展开大小、校验计算量、chunk 数分别检查。拒绝空镜像和非完整 raw 块。使用合成语料，保留适用 AOSP 通知。

## 风格与测试证据

使用两个空格缩进及 `moon fmt`。MoonBit 函数/文件用 `snake_case`，类型/构造器用 `PascalCase`。代码、测试标识符和提交信息使用英文；仓库文档仅使用中文，禁止表情符号。

公共测试用 `*_test.mbt`，内部测试用 `*_wbtest.mbt`，按行为命名。独立于 writer 构造语料，覆盖 chunk 类型、错误长度、输入分段、溢出、CRC、取消及限额。没有覆盖率百分比门槛，按 `handbook/verification-ledger.md` 验收。不得把 `--prepare` 当作 AOSP 已执行，也不能用 `simg2img` 作 CRC oracle。

## 提交与评审

使用 Conventional Commits，按独立实现、测试或文档工作组织提交。PR 说明行为、验证台账条目、准确命令/结果及未完成检查，同步相关文档。

凭据、个人资料和本地制品不得提交。native 支持和完整差分验收必须有执行证据。
