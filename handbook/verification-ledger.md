# 验证台账

[项目](../README.md) · [镜像合同](image-contract.md)

勾选仅证明所述条件；未勾选项可能已有较多本地覆盖，但仍需独立或平台证据。本地检查不等于完整发布验收。

## 已记录的执行证据

| 已执行检查 | 记录结果 |
| --- | --- |
| `pnpm test` | 格式、拒绝警告的检查、构建；wasm-gc/JavaScript 各 32 项测试，独立语料及 CRC 向量 |
| `pnpm test:host` | 独立预期 raw 字节、CRC 失败清理、字面零语义、覆盖保护、输出限额、非完整块拒绝、有界 sink 及注入 sink 故障 |
| `pnpm build` | 桥生成和检查器生产构建通过 |
| 浏览器审阅 | 合成检查、CRC、筛选/分配图、JSON 导出、坏输入/CRC 错误、取消后恢复；桌面/手机审阅，手机无横向溢出、console error 为零 |
| 参考准备 | 真实 MoonBit 桥生成合成语料/哈希记录，标记 `aospExecuted: false` |

2026-11-02 已运行并通过 `pnpm test`、`pnpm build`、`pnpm test:host`、合成示例 CRC 检查和 `reference/aosp/compare.mjs --prepare`。AOSP 链接 harness 尚未执行，其独立构建需要 g++/android-base 开发依赖；prepare 不等于独立差分验证。

## 表示与数据含义

- [ ] **四类 chunk 与版本策略。** 本地覆盖 RAW/FILL/DONT_CARE/CRC32 及最大长度扩展头；待执行固定 AOSP API harness 对照。
- [ ] **长度、总量、算术。** 本地对抗语料、所有截断点、字段偏移、u64 边界通过；待独立 AOSP 导入及更广语料。
- [ ] **CRC 一致性。** 独立逐位 CRC、已知向量、前缀/多 CRC chunk、头校验本地通过；待实际 AOSP 生成/验证的混合 Fill/Skip 语料及 `sparse_file_import(..., crc=true)`。
- [ ] **Skip 与零语义。** 本地事件区分、chunk 类型、RAW/FILL(0) 零打包通过；待独立预填充目标应用模型。
- [x] **序列化大小与尾块。** 已知 pieces 预检拒绝总块数溢出及非完整块；Bytes 大小 RAW payload 可放入 u32 长度，不宣称巨大输入流式拆 chunk。

## 增量执行与预算

- [x] **分段无关。** 单字节、不规则、完整缓冲输入保留相同元数据和拼接逻辑输出；RAW 片段边界可不同。
- [ ] **有计量的有界展开。** 已有固定 28 字节暂存、巨大空洞计数、64 KiB 主机 sink 调用及限额；待更广端到端内存计量和独立 Bytes 展开 API 验收。
- [ ] **失败传播与输出发布。** 回调取消、失效/重入、CRC 清理、输出保护、注入 JavaScript sink 错误本地通过；待文件系统读写故障注入及更广文件系统证据。
- [x] **已知 pieces writer。** 首次写出前检查全部 pieces/长度；`write_sparse` 流式处理已知 pieces，`pack` 持有有界 raw Bytes，不保证通用单遍 raw 输入。
- [x] **独立限额。** 展开量、CRC 工作量、chunk 数分别提前检查；核心默认 64 GiB、256 MiB、1,000,000 个 chunk，检查器/校验器为 10,000 个。

## 完整使用流程

- [ ] **固件分析。** 本地 inspect/validate/expand 匹配独立预期字节；待固定 AOSP 展开对照。
- [ ] **镜像构建。** 本地 pack/inspect/expand 和零数据检查通过；待 AOSP 接受/展开并验证拒绝非完整尾块策略。
- [ ] **流水线输入验证。** 本地错误附带偏移/消息，Node 拒绝 CRC 和限额错误；待更广独立对抗报告及流程。

## 平台与交付声明

- [ ] **主机/平台证据。** wasm-gc/JavaScript 核心、Node 主机、桌面/手机浏览器检查通过；待 Linux/native 流式/参考集成及其他适配。
- [ ] **自动化复现。** 本地检查/构建脚本已运行；待 CI 配置/执行、接口检查及干净 checkout/参考证据。
- [ ] **独立制品来源。** 已有 LICENSE/NOTICE、source pin、合成生成器和 prepare 哈希；待归档 AOSP 语料、真实输出、源码/二进制/语料哈希。
- [x] **范围声明。** 排除设备写入、resparse、USB、文件系统、boot-image 解析；浏览器仅为本地演示。2026-11-02 已复查重复。私有 GitHub 源码托管已配置，模块尚未发布至 Mooncakes。

## 关闭独立验证项

用 `reference/aosp/build.sh` 构建未修改的 AOSP 版本 `f7b2fc8117d44a26866f87392acbc5ad5c54d7a7`，再执行不带 `--prepare` 的 `reference/aosp/compare.mjs`。缓存路径通过显式参数或 `SPARSE_REFERENCE_CACHE` 设置，Windows 可通过 `--wsl=<distribution>` 指定 Linux 环境。保存双向转换真实结果、编译器/工具版本及哈希后，再勾选依赖条目。

`simg2img` 关闭 importer CRC，不能作 CRC oracle。对照时记录[镜像合同](image-contract.md)中的刻意更严格策略。上游混合 FILL/Skip writer CRC 疑点仅为源码观察，须先测未修改参考实现，不能称为已复现缺陷。
