# 为什么处理 Android Sparse

[项目](../README.md) · [验证台账](verification-ledger.md)

## 主机侧固件容器

Android sparse-v1 以 RAW 字节、重复四字节模式、显式跳过区域存储块对齐镜像，并可携带 CRC32。它不同于稀疏矩阵数学，也不同于 Intel HEX/SREC 地址记录格式。

[AOSP fastboot](https://github.com/aosp-mirror/platform_system_core/blob/main/fastboot/fastboot.cpp) 通过 libsparse 导入 raw/sparse 镜像。[独立 android-simg2img](https://github.com/anestisb/android-simg2img) 提供无需完整 AOSP 构建链的转换。这些用途支持可复用 MoonBit 表示与有界主机流程的价值，但不证明本项目已有下游采用。

目标使用者是固件分析者、镜像构建者、流水线维护者，任务包括比较存储与逻辑范围、展开前校验、由自有完整块数据生成 sparse。没有 MoonBit 下游用户承诺采用。

## 固定源码，显式对照

参考版本为 [AOSP libsparse f7b2fc8117d44a26866f87392acbc5ad5c54d7a7](https://github.com/aosp-mirror/platform_system_core/tree/f7b2fc8117d44a26866f87392acbc5ad5c54d7a7/libsparse)。已阅读 `sparse_format.h`、`include/sparse/sparse.h`、`Android.bp`、`sparse_fuzzer.cpp`、`img2simg.cpp`、`simg2img.cpp`。

格式允许扩展头，使用 32 位块数/计数字段。CRC 覆盖展开逻辑数据，跳过范围按零计算。`img2simg` 默认 NORMAL 输入模式，`-s` 选择 HOLE；`simg2img` 关闭 importer CRC。

`reference/aosp/` 保存构建脚本、C++ API harness、对照执行器。已运行合成准备流程，尚未运行 AOSP 链接可执行文件。完整验收需独立生成的确定性 raw、AOSP 写出的混合 chunk、双向转换、启用 CRC 的导入及哈希记录。详见[验证台账](verification-ledger.md)；阅读源码不等于执行证据。

## 公开检索发现

2026-11-01 初查覆盖 3,518 条 Mooncakes 记录、GitHub 仓库/代码及格式别名；2026-11-02 复查覆盖 3,520 条注册表记录、11 个仓库查询、8 个格式专用代码查询。在这些范围内未找到等价公开 MoonBit Android sparse-v1 codec。注明日期的机器记录在 [`provenance/discovery/`](../provenance/discovery/)，包括[复查记录](../provenance/discovery/recheck-2026-11-02.json)。

| 已阅读的附近项目 | 职责差异 |
| --- | --- |
| [moonbit-sparse-math](https://github.com/hp0200/moonbit-sparse-math) | CSR 矩阵/向量数学 |
| [firmware-image-toolkit](https://github.com/Zzqy-yi/moonbit-firmware-image) | Intel HEX/S-record 编解码与地址图 |
| [moon-firmware](https://github.com/SongYZZZ/moon-firmware) | 使用 HEX/SREC 稀疏地址图的 NOR 更新规划 |
| [MoonFetchLedger](https://github.com/cn-wn/moonfetchledger) | 跨版本块恢复/检查点流程 |
| [moon-uf2](https://github.com/Trylaney/moon-uf2) / [MoonUF2](https://github.com/ssjssj183312-jpg/MoonUF2) | UF2 512 字节固件块 |

注册表元数据和公开索引不会覆盖私有、未索引、未发布实现，语言筛选也可能遗漏混合仓库。因此结论有明确范围，不声称绝对没有其他实现或开发者。检索记录不是 codec 测试结果。

## 许可与自有语料

项目包含 Apache-2.0 `LICENSE` 和 `NOTICE`，复用 AOSP 代码须保留适用上游通知。独立工具仓库缺失的许可元数据不能作为许可依据。语料为确定性合成数据，不再分发厂商固件；设备写入与刷机不在范围内。
