# Stremio-IPA

把官方 [Stremio/stremio-web](https://github.com/Stremio/stremio-web) 打包成 iOS 应用：网页产物**离线塞进 App 里**，用 GitHub Actions 在云端编译出**未签名 IPA**。

> 本项目与 Stremio 官方无关，只是个人自用的打包壳。stremio-web 本体版权属于 Smart Code OOD，遵循其 GPL-2.0 许可。

## 这是什么

- `stremio-web` 是一个纯网页 React 应用，本身没有 iOS 工程。本仓库给它套了一个极简的 iOS 壳：
  - Swift + WKWebView 全屏加载，Bundle ID：`com.zhihenglu.stremio`，最低 iOS 16。
  - 工程用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 描述（`project.yml`），不手写 `.xcodeproj`。
- 每次构建时，Actions 会现拉 `Stremio/stremio-web` 源码、用 Node 22 + pnpm 11 构建出静态产物，再塞进 App 一起打包。所以 IPA 里的 Stremio 版本取决于构建那一刻上游的最新代码。

## 离线打包原理（关键设计）

直接用 `file://` 打开网页产物行不通：Stremio 的核心引擎（Rust 编译的 WASM）跑在一个 Web Worker 里（`new Worker("<提交哈希>/scripts/worker.js")`），`file://` 下 Worker、WASM 和 fetch 都会被同源策略拦死。

本壳的做法（见 `Sources/Stremio/LocalWebSchemeHandler.swift`）：

- 注册自定义 scheme `stremioapp://localhost/`，由 `WKURLSchemeHandler` 从 Bundle 的 `web/` 目录读文件返回，相当于一个内置的本地静态服务器。
- 返回时带正确 MIME，尤其 `.wasm → application/wasm`、`.js → text/javascript`，WASM 才能正常编译加载。
- 这个 handler **只管自定义 scheme**，不拦截 http/https：插件 API、图片、视频流等网络请求全部正常联网。所以“离线”指的是界面和程序本身不依赖 web.strem.io 服务器，真正看片仍然需要网络。
- 上游的 Service Worker 更新机制在离线包里关掉了（构建时传 `SERVICE_WORKER_DISABLED=true`）：自定义 scheme 下 SW 无法注册，关掉避免无意义的报错。

## 怎么拿到 IPA

1. 打开本仓库的 **Releases** 页，下载最新一条 Release 里的 `Stremio-unsigned.ipa`。
2. 或者打开 **Actions → Build unsigned IPA**，在某次成功运行的底部 **Artifacts** 里下载 `Stremio-unsigned-ipa`（Artifact 有保留天数，长期保存请用 Release）。

## IPA 未签名，怎么装

这个 IPA **没有苹果签名，不能直接点开安装**，这是自打包应用的常态。常用办法：

- **AltStore / SideStore**：用你的 Apple ID 自签后装到手机上（免费账号签名 7 天过期，SideStore 可在手机上自动续签）。
- 有巨魔（TrollStore）环境的设备可以直接安装。

## 如何手动触发构建

1. 打开仓库页 → **Actions** → 左侧选 **Build unsigned IPA**。
2. 点 **Run workflow** → 分支选 `main` → **Run workflow**。
3. 约十几到几十分钟后（要现构建 stremio-web），到该次运行的 Artifacts 或仓库 Releases 里下载 IPA。

推送到 `main` 也会自动触发构建；但如果仓库文件是由 GitHub App / 令牌推送的，GitHub 出于防循环限制可能不自动触发，这时按上面步骤手动点一次即可。

## 已知限制

- **种子流播不了（除非配外部服务）**：手机里没有 Stremio 桌面版那个本地 Streaming Server，磁力/种子类资源需要配合 Real-Debrid 等 Debrid 服务、自建 Streaming Server，或用插件提供的直链源。
- **播放能力受 iOS 限制**：WKWebView 只能解 iOS 原生支持的格式（如 MP4/H.264、HLS），MKV、部分编码的外挂字幕/音轨可能播不了或没声音，这是苹果平台的硬限制，壳解决不了。
- **未经真机充分验证**：自定义 scheme 下 Web Worker + WASM 的加载路径是按网页规范设计的，构建成功不等于真机一切正常；如果装上后卡在加载界面，多半是这条链路的问题，请到 Issues 里反馈手机型号和 iOS 版本。
- 登录、插件商店等功能走官方接口，需要正常联网；部分插件是 http 明文地址，壳里已放行（ATS `NSAllowsArbitraryLoads`）。

## 目录说明

| 路径 | 说明 |
|---|---|
| `project.yml` | XcodeGen 工程定义 |
| `Sources/Stremio/` | Swift 壳源码（WebView、scheme handler） |
| `Resources/Assets.xcassets/` | 图标/颜色（图标在构建时由上游 Stremio 图标生成） |
| `web/` | 占位目录，构建时被 stremio-web 产物替换，不进仓库 |
| `.github/workflows/build-ipa.yml` | 构建流水线：拉上游 → 构建 web → 生成工程 → 编未签名 IPA → 发 Release |

## 本地开发（有 Mac 时）

```bash
brew install xcodegen
# 先把 stremio-web 构建产物放进 web/，再：
xcodegen generate
open Stremio.xcodeproj
```

没有 web 产物时 App 也能打开，会显示一个“网页文件未打包”的说明页。
