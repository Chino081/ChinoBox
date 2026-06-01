# ChinoBox

这是对 [670848654/MoviesBox](https://github.com/670848654/MoviesBox) 的 Flutter/Dart 迁移版本，目标平台为 Android 和 Windows。

原项目采用 MIT License，本项目继续遵守 MIT License，并保留原项目来源说明。

## 用途声明

本项目仅用于 Flutter/Dart 跨平台开发、HTML 解析与公开网页内容聚合技术学习交流。应用不提供、不存储、不分发任何影视资源，所有网络内容均来自用户可访问的公开页面。

本项目不会实现：

- VIP 解析、付费内容解析或第三方解析接口
- 登录绕过、Cookie 硬编码、DRM 绕过
- Cloudflare/反爬/浏览器安全检测绕过
- 视频嗅探绕过
- 广告切片过滤或离线传播能力

## 已支持功能

- Android 和 Windows 工程配置
- 首页推荐、分类浏览、影视/动漫列表
- 站点切换和站点状态标记
- 搜索
- 详情页、剧集和播放源列表
- 使用 `media_kit` 播放公开直链 `m3u8/mp4`
- 收藏
- 播放历史与进度记录
- 本地页面缓存
- 加载、空状态、错误状态与重试
- 代理设置、站点自定义域名和可选站点 Cookie

## 支持站点

| 类型 | 站点 | 状态 |
| --- | --- | --- |
| 影视 | 拖布影视 | 正常 |
| 动漫 | 嘶哩嘶哩 | 需在设置页为该站点填写 Cookie；不硬编码 Cookie |
| 动漫 | 樱花动漫 | 首页/分类/详情可用，搜索禁用 |
| 动漫 | AnFuns | 隐藏，后续修复后开放 |
| 影视 | LIBVIO | 正常 |
| 影视 | 在线之家 | 隐藏，后续修复后开放 |
| 影视 | 555电影 | 隐藏，后续修复后开放 |
| 影视 | 雪落影视 | 正常（搜索可能需要站点验证） |
| 影视 | 小宝影院 | 隐藏，后续修复后开放 |
| 影视 | 纽约影院 | 隐藏，后续修复后开放 |
| 动漫 | ギリギリ愛 | 部分异常（搜索可能需要站点验证） |

站点关闭或不可用时，应用会显示提示，不会崩溃。

## 运行

本机已验证 Flutter 3.44.0、Android SDK 36、Windows Build Tools 2022 可用。

```powershell
flutter pub get
flutter run -d windows
flutter run -d android
```

## 构建

```powershell
flutter build windows --release
flutter build apk --release
```

已生成的本地构建产物：

- Windows: `build/windows/x64/runner/Release/ChinoBox.exe`
- Android: `build/app/outputs/flutter-apk/app-release.apk`

Windows 需要整个 `build/windows/x64/runner/Release` 目录一起分发，不能只复制 exe。

## 代理配置

应用设置页可以填写代理地址，也可以在运行前通过环境变量提供：

```powershell
$env:MOVIESBOX_PROXY="socks5://user:password@host:port"
flutter run -d windows
```

代理、Cookie、密钥和用户隐私信息不得写入源码或提交记录。

嘶哩嘶哩这类站点如果要求访问 Cookie，可以在“设置 / 当前站点”里为当前站点填写 Cookie。该值仅保存在本机应用设置中，不会写入源码。

也可以在本机构建时通过 `MOVIESBOX_SILISILI_COOKIE` 注入默认 Cookie，用于你自己的本地运行，不建议提交到仓库。

## 迁移说明

完整迁移分析见 [docs/MIGRATION.md](docs/MIGRATION.md)。
