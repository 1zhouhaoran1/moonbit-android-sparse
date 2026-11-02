# 镜像操作配方

[项目](../README.md) · [镜像合同](image-contract.md)

在仓库根目录运行，环境为 Node.js 22+、pnpm、MoonBit。只使用 pnpm。`pnpm install` 后，MoonBit 代码每次变化都需运行 `pnpm build:codec`；生成的主机 JavaScript 不作为源码提交。

## 检查存储表示

```sh
pnpm sample
pnpm cli inspect output/synthetic.sparse.img --json
pnpm cli inspect output/synthetic.sparse.img --json --crc
```

`pnpm sample` 会主动重新生成标注为合成数据的文件。`inspect` 报告存储/逻辑偏移、头及 chunk 类型。加 `--crc` 可在独立 CRC 预算内校验累计数据；不加时避免为 CRC 处理展开空洞。

浏览器视图运行 `pnpm dev`，打开 `http://127.0.0.1:5178`。选择本地文件或标注的合成示例；worker 每次读取 1 MiB。可使用取消、chunk 筛选、分配图、分页及 JSON 导出。文件不上传，服务器使用严格固定端口。

## 校验与转换

```sh
pnpm cli validate output/synthetic.sparse.img --json
pnpm cli expand output/synthetic.sparse.img output/expanded.raw --max-output 33554432
pnpm cli pack output/expanded.raw output/repacked.sparse.img --block-size 4096
```

| 选项 | 含义 |
| --- | --- |
| `--json` | 输出机器可读报告 |
| `--crc` / `--no-crc` | 控制 inspect/validate/expand 的 CRC，互斥；validate/expand 默认开启；pack 始终写入 CRC |
| `--max-output N` | 展开或序列化输出字节上限，为正安全整数 |
| `--block-size N` | pack 块大小，默认 4096，须为四的正倍数 |
| `--force` | 显式允许替换目标 |

输入必须为普通文件，转换输入输出路径须不同，目标目录须已存在。失败会删除临时文件。不带 `--force` 时，发布过程拒绝已有或竞争出现的目标。pack 拒绝空输入、非完整块、大于 64 MiB 的输入，以及大于独立 64 MiB 上限的序列化输出；增大 `--max-output` 不会解除该上限。

## 检查源码改动

```sh
pnpm test
pnpm build
pnpm test:host
```

`tooling/verify-core.mjs` 在 wasm-gc/JavaScript 上执行格式检查、拒绝警告的类型检查、构建及测试。`tooling/verify-host.mjs` 检查独立预期字节、转换失败、零语义、覆盖保护及限额。`pnpm build` 重新生成桥并检查/构建检查器。审查公共接口变化时运行 `moon info`。剩余独立检查见[验证台账](verification-ledger.md)。

## 准备独立对照

```sh
node reference/aosp/compare.mjs --prepare
```

prepare 会运行真实桥并生成合成语料/哈希记录，明确不执行 AOSP。需要自定义缓存时，在命令中以实际路径替换 `<cache-directory>`，作为可选目录参数传入。

参考工具需在具备 g++、zlib、android-base 开发依赖的 Linux 环境中构建。用 `reference/aosp/build.sh` 构建未修改的固定参考版本，再运行不带 `--prepare` 的对照。Windows 主机可通过 Linux 环境执行参考对照；这不构成 Windows native 验证。归档实际源码/二进制/语料哈希及双向转换结果；`simg2img` 不验证 CRC。
