# MoonBit Android Sparse

[镜像合同](handbook/image-contract.md) · [操作配方](handbook/command-recipes.md) · [验证台账](handbook/verification-ledger.md)

读取 Android sparse 镜像布局、检查完整性，并在 sparse 与完整块 raw 文件之间转换。增量编解码核心使用纯 MoonBit 编写，Node 命令行与本地浏览器检查器共用其 JavaScript 桥。

模块名：`1zhouhaoran1/android_sparse`。源码保存在[项目私有仓库](https://github.com/1zhouhaoran1/moonbit-android-sparse)。模块尚未发布至 Mooncakes。

## 从一份镜像开始

需要 Node.js 22+、pnpm 和 MoonBit。已记录的本地工具链为 moon `0.1.20261028`、moonc `v0.10.18+6c83a7f62`。

```sh
pnpm install
pnpm build:codec
pnpm sample
pnpm cli inspect output/synthetic.sparse.img --json
```

合成示例以 4,196 个存储字节，通过 RAW、FILL、DONT_CARE、CRC32 chunk 描述 32,768 个逻辑字节。替换路径即可检查自己的镜像头、chunk 偏移和逻辑范围。不带 `--crc` 的检查只读取存储表示，不对展开后的空洞计算校验和。

需要可视布局时运行 `pnpm dev`，打开 `http://127.0.0.1:5178`。检查器通过 worker 读取本地所选文件，展示分配台账并导出 JSON，不上传文件。端口固定为 5178，占用时直接报错。

## 先校验，再转换

```sh
pnpm cli validate output/synthetic.sparse.img --json
pnpm cli expand output/synthetic.sparse.img output/expanded.raw --max-output 33554432
pnpm cli pack output/expanded.raw output/repacked.sparse.img --block-size 4096
```

`validate`、`expand` 默认验证 CRC；`inspect` 需加 `--crc`。这三条命令可用 `--no-crc` 关闭校验计算；`pack` 始终写入 CRC。转换先写临时文件，仅在成功后发布目标；覆盖已有目标需 `--force`，输入输出路径必须不同。

pack 只接受非空完整块，拒绝不足整块的尾部。便捷命令最多持有 64 MiB raw 输入，序列化输出也最多 64 MiB。命令选项见[操作配方](handbook/command-recipes.md)。

## 分清三种大小

| 度量 | 含义 | 默认边界 |
| --- | --- | --- |
| 存储字节 | sparse 文件实际读取的头与编码 payload | 增量读取，检查 chunk 长度及总量 |
| 逻辑字节 | 块数乘块大小，包含跳过区域 | 核心/检查器展开上限 64 GiB |
| CRC 计算量 | 完整性校验实际处理的展开前缀 | 256 MiB，独立于逻辑大小限额 |

核心调用者可独立设置限额，默认最多 1,000,000 个 chunk；检查器/校验器最多保留 10,000 个。Node 展开每次向 sink 输出不超过 64 KiB。不实体化逻辑内容即可检查巨大空洞，但计算空洞 CRC 仍需与展开字节数成比例的工作。

**跳过区域不等于请求写零。** 核心保留 `SkipData`，只有显式 `Hole` 在写出时成为 DONT_CARE；字面零输入仍是 RAW 或 FILL(0)。向新 raw 文件展开时，跳过区域填零，这不定义已有设备应如何更新。[镜像合同](handbook/image-contract.md)解释其差别及兼容策略。

## 按职责找代码

```text
kernel/                 纯 decoder、writer、CRC、类型及同包测试
  javascript/           共用主机桥
host/                   Node 命令行与合成样本生成器
inspector/              React/Vite/TypeScript/Tailwind 本地检查器
tooling/                编译与验证
reference/aosp/         固定版本的独立对照 harness
handbook/               合同、配方、验证与格式背景
provenance/discovery/   注明日期的公开检索记录
```

桥接 JavaScript、构建产物和 `output/` 都是可再生制品。修改 MoonBit 源码后，用 `pnpm build:codec` 重新生成主机代码。

## 证据能说明什么

已记录的本地运行通过 `pnpm test`：wasm-gc、JavaScript 各 32 项测试，且 `pnpm test:host`、`pnpm build` 通过。浏览器检查覆盖镜像检查、CRC、筛选、分配图交互、JSON 导出、错误及取消后恢复；桌面/手机审阅确认手机无横向溢出、console error 为零。

独立 AOSP 执行、native 主机适配、CI 和完整发布验收仍待完成。参考准备流程生成语料/哈希，标记 `aospExecuted: false`，没有执行 AOSP。[验证台账](handbook/verification-ledger.md)分别记录本地结果和剩余要求。

Android sparse-v1 是存储/传输容器。范围排除 resparse、fastboot、USB、设备写入、ext4/EROFS、dynamic-super、boot-image 解析和任意压缩封装。[格式背景](handbook/format-context.md)记录 AOSP 源码固定版本、查重及许可依据。代码采用 Apache-2.0，保留 `LICENSE` 和适用 `NOTICE` 条目。
