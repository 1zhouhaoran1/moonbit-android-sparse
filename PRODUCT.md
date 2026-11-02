# 产品说明

<!-- impeccable:product-schema 1 -->

## 平台

web

## 技术栈

使用 React、Vite、TypeScript、TailwindCSS。浏览器调用 MoonBit 编译出的 JavaScript；无需服务器或数据库。

## 使用者

固件分析者，以及评估 Android sparse 镜像编解码库的开发者。

## 产品目标

检查本地 Android sparse-v1 文件结构并报告验证错误，文件不上传。库与 Node CLI 支持 raw/sparse 转换；独立 AOSP 互操作验收尚未完成。

## 使用场景

选择本地镜像，或运行明确标注的合成示例。Worker 分段读取文件，调用与 CLI 相同的 MoonBit decoder。

## 能力与限制

初版演示关注文件头、chunk 布局和结构验证。CRC 验证须显式选择，并单独限制计算量。文件大小与逻辑展开大小分开显示。Skip 不等价于覆盖写零。不访问设备、不刷机、不解析文件系统。

## 品牌约定

沿用 MoonBit Android Sparse 名称。使用简短功能标签和清晰工作区。不编造用户采用、性能或验收结论。

## 已有依据

README.md 描述可运行的编解码器；handbook/verification-ledger.md 区分本地检查与待完成的独立验收。合成示例须明确标注，不包含厂商固件。

## 产品原则

- 保留二进制格式语义。
- 文件留在用户本地。
- 限制内存与计算量。
- 错误须便于处理，明确区分 CRC 未验证与已验证。

## 未定事项

仓库与模块归属 1zhouhaoran1。浏览器已实现文件检查流程；托管方式与公开发布仍未确定。
