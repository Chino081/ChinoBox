# ChinoBox 迁移清单

## 分析来源

- 本地参考源码：`_reference/MoviesBox-master`，来自用户提供的 `MoviesBox-master.zip`
- README：支持站点、用途声明、MIT License
- Android 源码：`SourceEnum`、`ParserInterface`、各 `parserImpl`、Room 实体、Activity/Fragment、设置与播放字符串
- Releases：GitHub 页面可见最新公开 Release 为 `1.2.4`，本地 master 源码 `app/build.gradle` 标记为 `1.2.5`
- Issues：GitHub 仓库导航显示 Issues 数量为 3；当前环境无法稳定展开详情，因此未把不可见详情作为迁移依据

## 原功能清单

| 模块 | 原项目功能 | Flutter 迁移状态 |
| --- | --- | --- |
| 首页 | 站点首页推荐、轮播、横向列表、多样式列表 | 已迁移为简洁分区列表 |
| 站点切换 | 影视/动漫源切换，按状态过滤关闭站点 | 已迁移，关闭站点保留但禁用 |
| 分类 | 分类组、分类列表、分页 | 已迁移基础分类入口和分页 |
| 搜索 | 关键词搜索、搜索历史、部分站点验证页 | 已迁移搜索；雪落/樱花/ギリギリ愛支持验证码输入 |
| 详情 | 海报、标题、评分、描述、标签、推荐 | 已迁移 |
| 剧集 | 多播放源、选集、当前播放源剧集 | 已迁移基础多播放源/剧集 |
| 播放 | 内置/外置播放器、Exo/Ijk、倍速、全屏、下一集、PiP | Flutter 版使用 `media_kit`；保留基础播放，未实现 Android PiP/外置播放器 |
| 弹幕 | XML/JSON 弹幕策略，部分站点弹幕接口 | 未迁移，后续可加合法公开弹幕接口 |
| 收藏 | 收藏、取消收藏、目录管理 | 已迁移收藏；目录管理暂未迁移 |
| 历史 | 播放历史、进度、隐藏记录 | 已迁移历史和进度记录 |
| 下载 | MP4/M3U8 下载、Aria、切片队列、广告切片规则 | 未迁移，避免离线传播与广告切片过滤 |
| 本地缓存 | 图片缓存、页面缓存、Room DB | 已迁移页面缓存、收藏/历史本地存储 |
| 设置 | 域名配置、域名更新 API、播放器、主题、缓存、备份恢复、更新检查 | 已迁移域名、代理、站点 Cookie、主题、缓存；备份、更新检查暂未迁移 |
| 代理 | 原项目未做统一代理设置，部分站点备注需代理 | Flutter 版新增代理设置，支持 `MOVIESBOX_PROXY` |
| 网络 | OkHttp、超时、请求头、Cookie、POST | 已迁移 Dio、超时、重试、User-Agent、站点请求头；可本地配置站点 Cookie，但不硬编码或打印 |
| 站点域名 | 用户可覆盖默认域名，部分发布页解析 | 已迁移手动域名覆盖；自动解析发布页暂未迁移 |
| 图片预览 | 封面预览、懒加载图片 | 使用 Flutter 图片加载，未单独实现预览页 |
| DLNA/投屏 | UPnP/DLNA 服务 | 未迁移 |
| VIP 解析助手 | 第三方 VIP 解析接口、Intent 分享入口 | 不迁移，属于明确排除项 |
| 视频嗅探 | 常规解析失败时 WebView 嗅探视频 | 不迁移，属于明确排除项 |
| Cloudflare 绕过 | FuckCFService 尝试绕过安全检测 | 不迁移，属于明确排除项 |
| 日志 | 本地解析日志、异常处理 | 保留开发日志框架，不输出敏感信息 |

## Flutter 迁移映射表

| Java/Android | Flutter/Dart |
| --- | --- |
| `ParserInterface` | `SiteParser` |
| `SourceEnum` | `MediaSource` + `sourceCatalog` |
| `parserImpl/*` | `lib/src/features/content/data/parsers/*_parser.dart` |
| `OkHttpUtils` | `MoviesHttpClient` |
| `Room` 表 `TVideo/TFavorite/THistory/*` | `shared_preferences` JSON 存储 `FavoriteEntry/HistoryEntry` |
| `HomeActivity/HomeFragment` | `HomeShellPage/HomePage` |
| `SearchActivity` | `SearchPage` |
| `VodListActivity/ClassificationVodListActivity` | `BrowsePage` |
| `DetailsActivity` | `DetailPage` |
| `PlayerActivity` | `PlayerPage` + `media_kit` |
| `SettingFragment` | `SettingsPage` |
| `FavoriteFragment/HistoryFragment` | `LibraryPage` |

## 站点状态

| 站点 | 原项目状态 | Flutter 版处理 |
| --- | --- | --- |
| 拖布影视 | 正常 | 已按当前页面结构补专用 Parser |
| 嘶哩嘶哩 | 原源码标注正常，但 parser 硬编码站点访问 Cookie，默认域名为 `https://www.sssfun.cc` | 已改回原项目域名；设置页支持为该站点填写 Cookie，也可用构建参数注入本地默认 Cookie，不在源码硬编码个人会话 |
| 樱花动漫 | 原源码标注正常，`.io` 注释可跳转当前 `.cc` 域名 | 已切到 `https://www.iyinghua.cc`，首页/分类/详情/搜索验证码可用 |
| AnFuns | 隐藏 | 保留结构，后续修复后开放 |
| LIBVIO | 正常 | 已按当前详情页/播放页结构补专用 Parser，并向播放器透传请求头 |
| 在线之家 | 隐藏 | 保留结构，后续修复后开放 |
| 555电影 | 隐藏 | 保留结构，后续修复后开放 |
| 雪落影视 | 正常 | 已补播放页公开直链解析；搜索支持验证码输入 |
| 小宝影院 | 隐藏 | 保留结构，后续修复后开放 |
| 纽约影院 | 隐藏 | 保留结构，后续修复后开放 |
| ギリギリ愛 | 正常 | 已按当前页面结构补专用 Parser；搜索支持验证码输入 |

## 合规裁剪

以下原功能没有迁移到 Flutter 版：

- VIP 视频解析助手
- Cloudflare 或浏览器安全检测绕过
- 视频嗅探绕过
- 登录态、Cookie、密钥、代理凭据硬编码
- M3U8 广告切片过滤、离线下载

Flutter 版只尝试解析公开页面中直接暴露的 `m3u8/mp4` 地址；如果播放地址需要加密脚本、登录、验证、DRM 或第三方解析接口，会返回错误状态，而不是绕过。
