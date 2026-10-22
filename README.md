# 奈鹿 NaiLu 客户端

基于 [FlClash](https://github.com/chen08209/FlClash) 二次开发，接入 `https://nailu.pro`。目标为 Android、Windows 和 macOS。保留上游代理核心、配置管理和连接生命周期。

上游基线：`8d4f9744948751f1273fe871e1d05276fac09b0e`。版本：`0.1.2+2026102301`。主应用标识：`pro.nailu.client`。独立 Windows 安装器标识、Helper 服务和应用数据目录避免与 FlClash 安装互相覆盖。

## 使用流程

1. 首次打开客户端，必须在奈鹿登录页输入官网邮箱和密码，并完成 Cloudflare 验证。
2. 客户端通过 HTTPS 调用现有 `POST /api/v1/passport/auth/login`，提交 `cf-turnstile-response`；沿用服务器校验，不增加免验证入口。
3. 服务器确认账号及订阅后进入主界面，自动同步 mihomo 订阅；未购买套餐可进入账户页购买。
4. 选择节点并连接。注册入口在 App 内打开奈鹿官网注册页，保留现有 Cloudflare 和注册防护，成功后返回邮箱密码登录。找回密码、续费和工单打开奈鹿官网。
5. 再次打开会向后端验证系统安全存储中的会话，验证成功免重复输入密码；网络失败或会话过期停留在登录页。

默认不持久保存密码。勾选“记住账号和密码”后，邮箱及密码写入系统安全存储；退出登录仍保留，取消勾选会删除。登录表单中的密码在成功后清空。会话保存在系统安全存储中。登录前不执行自动连接，托盘和快捷入口也经过登录状态检查。退出登录会先停止连接，再删除托管订阅并清理本地会话。

将 `backend/nailu-client-challenge.html` 部署到 `nailu.pro` 网站的 `public/` 根目录。该页面仅承载 Cloudflare 验证，只有公开 Site Key，Secret Key 必须保留在后端。验证码必须由使用者本人完成。Windows 用户需安装 Microsoft Edge WebView2 Runtime，Android 需可用的系统 WebView；验证加载失败可重新加载，不会放行登录。

旧版浏览器设备授权接口保留兼容，新版强制登录页不使用浏览器授权代替邮箱密码登录。

订阅仅接受奈鹿的七个 HTTPS 域名，使用后端 `flag=meta` 格式。首次安装默认不自动启动 VPN；已有自动运行设置只会在登录与订阅同步成功后生效。退出会先停止当前奈鹿配置、删除托管订阅，再撤销客户端会话；停止失败会提示重试。

## 构建

需要 Flutter `3.47.6`、Go `1.27.1`、Rust stable。Android 另需 JDK 17、SDK 37、Build Tools 37.0.0、NDK `28.2.13676358`。Windows 另需 NuGet CLI、Visual Studio 2022 C++ 桌面工具、ATL、Windows SDK 和 CMake。macOS 需要 Mac、Xcode 与 CocoaPods。验证 WebView 的 macOS 插件使用 CocoaPods，与其余 Swift Package Manager 插件混合构建。

Windows 上请使用较短的源码路径，避免 MSBuild 插件输出超过 260 个字符。若在 Windows 构建 Android，需要额外提供 Windows 宿主版 libclang，并将 `LIBCLANG_PATH` 指向包含 `libclang.dll` 的目录；Windows NDK 本身不包含这份宿主库。

```sh
git submodule update --init --recursive
flutter pub get
dart run intl_utils:generate
flutter analyze --no-fatal-infos
flutter build apk --release --split-per-abi
flutter build windows --release
flutter build macos --release
```

分别在对应系统运行平台构建命令。完整打包也可使用原有 `dart setup.dart <platform>`；Windows 安装包需要 Inno Setup，macOS DMG 需要 appdmg。

`.github/workflows/nailu.yaml` 提供手动触发的三端构建，只保存构建产物，不自动发布。原上游工作流存放在 `.github/upstream-workflows/`，不会向上游频道推送包。未设置奈鹿自己的更新仓库前，禁用自动检查上游 FlClash 更新。

本机运行仅用安全模式，避免改变正在使用的代理和网络设置：

```sh
flutter run --dart-define=SAFE_MODE=true
```

### Android 签名

支持以下环境变量，优先于本地 properties：

- `NAILU_ANDROID_KEYSTORE`：奈鹿自己的 JKS 文件绝对路径。
- `NAILU_ANDROID_STORE_PASSWORD`
- `NAILU_ANDROID_KEY_PASSWORD`
- `NAILU_ANDROID_KEY_ALIAS`

CI 对应增加 `NAILU_ANDROID_KEYSTORE_BASE64` Secret。没有正式签名配置时，上游构建逻辑只生成 `.dev` 测试包，不能当作正式签名版本发布。签名私钥及密码不能提交 Git；必须单独备份，否则无法为已安装版本发布兼容更新。

macOS 使用独立 Keychain 项，关闭 Data Protection Keychain 共享，不要求额外 App Group。对外分发仍需使用用户自己的 Apple Developer ID 签名并公证。当前 CI 的 macOS 归档明确标为 unsigned。Windows 对外发布的 Authenticode 签名需另配证书。

### 图标

`assets/images/nailu.svg` 为奈鹿现有鹿形标识源文件。安装 Node 和 `sharp` 后运行 `node tool/nailu-icons.cjs`，生成启动图标、Windows ICO、macOS AppIcon、托盘图片与 Android 通知矢量图。保留 `assets_source/images/icon/` 作为状态图标源码。

### Windows 安装包

Windows 正式安装包通过 `tool/build-nailu-installer.ps1` 构建（可指定 `-Iscc` 和 `-OutputDirectory`）。安装向导提供应用目录、桌面“奈鹿 NaiLu”文件夹两种位置及桌面快捷方式复选框。文件关闭由 Windows Restart Manager 按安装文件处理，不按进程名强制结束其他安装。

安装包包含经 Microsoft 数字签名核验的 WebView2 引导程序，缺少运行环境时联网安装。不会在构建机安装或启动奈鹿客户端。

## 后台授权扩展

`backend/app/` 提供 V2board 路由和控制器；`backend/web/client-auth.patch` 是官网授权页补丁。控制器使用现有 `user` 中间件和 `AuthService`，不新增免验证密码登录接口。生产使用支持原子锁的 Redis Cache。

- `POST /api/v1/guest/nailu/client/start`
- `POST /api/v1/guest/nailu/client/poll`
- `GET /api/v1/user/nailu/client/details`
- `POST /api/v1/user/nailu/client/approve`

部署前备份目标文件，执行 PHP 语法检查和 `backend/tests/device-flow.php`，然后刷新 PHP FPM 与 Blade 缓存。网站 JS 使用新的内容指纹文件名。`backend/tests/http-smoke.php` 只在受控服务器 CLI 运行，会创建并清理临时会话，不应公开为 Web 文件。

## 验证与已知限制

奈鹿单元测试位于 `test/nailu/`，覆盖直接邮箱密码登录、验证码缺失、错误凭据、登录界面、强制登录拦截、离线恢复、订阅来源、授权取消和会话清理。桌面 Helper 与协议测试沿用上游测试。按照 `.agents/commands.md`，纯 Dart 测试可临时关闭两个原生 build hook，但必须恢复为 `true` 后才能打包。

上游若干 `test/lint/` 测试直接比较 Unix 路径，在 Windows 上会误报上游未改文件；不应通过放宽规则掩盖问题。实际界面仍遵循上游的图标、字体、圆角及加载组件约定。

尚需真机验证 Android VPN 授权、后台保活、Windows TUN 提权与 macOS 网络权限；编译成功不等于这些系统交互已完成验收。

## 开源许可

保留原始 `LICENSE` 和上游署名，遵守 GPL-3.0；对外分发二进制时同时提供对应完整源码、构建说明和许可。代理核心及第三方依赖保留各自许可。奈鹿品牌资产与源代码中的上游作者署名分别保留，不冒充上游官方发行版。
