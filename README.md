# 下班王 Flutter 客户端

Android / iOS 共用客户端；Web 是正式用户入口，支持添加到主屏幕和网页推送。

客户端仓库：[bus_remind_app](https://github.com/DengYuncheng27/bus_remind_app)。后端与 React 网页管理端独立维护于 [BusReminder](https://github.com/DengYuncheng27/BusReminder)，本仓库只通过 HTTP API 与后端通信。

## 已实现

- 登录、按后台开放策略注册、邀请码、会话恢复与续期；原生端凭据使用安全存储。
- 三个底部 Tab：乘车、提醒、我的。乘车首页直接展开一条常用线路的地图、最近一辆及后续车辆；提醒页集中管理通勤规则；我的页管理账号与手机通知。
- 首页支持切换常用线路并按账号在本机记忆，前台查看时每 30 秒更新当前线路，切换 Tab 后暂停自动查询。
- 同线路一键换向，自动匹配反方向同名上车站；找不到或有歧义时选站，不改变已有提醒。
- 三步创建：城市与线路方向 → 上车站 → 提前站数、日期规则、时间窗。
- 编辑提醒、永久暂停/恢复、今天暂停（北京时间次日零点自动恢复）、删除。
- 真实车辆查询，空数据、过期、网络错误状态，手动刷新。
- Android/iOS 极光推送接入、权限申请、设备注册/解绑、测试通知与点击跳转。
- 演示模式单独运行，不访问后台、不发送通知、不存储账号。

## 环境

验证版本为 Flutter 3.47.9 / Dart 3.13.7，Dart 最低版本约束见 `pubspec.yaml`。将 Flutter SDK 加入 PATH 后，在本仓库根目录运行：

```sh
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=https://bus.su7.space
```

正常构建默认连接真实后台。只有隔离的演示预览才显式传 `--dart-define=DEMO=true`，演示不会发送通知或访问用户账号。

本地静态预览先执行下面的 Web 构建，再运行 `python tool/serve_web.py`（本仓库根目录）。它在 `http://127.0.0.1:8765/` 提供带构建版本的 URL，禁用本地资源缓存并退出旧 Flutter Service Worker，保留现有登录和账号偏好。重新构建后刷新会自动跳转到新版本路径，避免浏览器继续显示旧界面。

本机连接真实后台的预览构建：`flutter --no-version-check build web --no-pub --dart-define=DEMO=false --dart-define=API_BASE_URL=https://bus.su7.space --dart-define=LOCAL_API_PROXY=true`。预览服务将 `/api/` 同源转发至固定的 `https://bus.su7.space`，保留 Bearer 身份验证和会话续期，不转发 Cookie，不接受任意上游地址。这解决旧线上 CORS 仅允许 GET/HEAD/POST 导致 PATCH 编辑、开关及 DELETE 被浏览器拦截的问题。开关仅在服务端成功响应后更新；发送期间禁用重复操作。

该转发仅用于 `127.0.0.1:8765` 的显式本地预览，不改变客户端服务器配置和登录存储键；原生版仍直接访问 HTTPS API。远程 Web 部署需部署后端仓库 `src/app.ts` 的 CORS 方法修正。代理不会补齐旧后端缺失的今天暂停或原生推送能力。代理测试：`python -m unittest discover -s tool -p test_serve_web.py`。

## 连接后台

公交查询和普通提醒使用已有 API。手机推送及今天暂停需要后端支持相应接口；客户端发布不代表后端已经升级。接口职责及兼容性见 [后端对接说明](docs/BACKEND.md)。数据库、推送密钥与提醒调度保留在后端仓库，本客户端不直接访问数据库。

```sh
flutter run --dart-define=API_BASE_URL=https://bus.su7.space
```

Android 模拟器调试可使用 `http://10.0.2.2:3000`，仅 debug 模式允许本地 HTTP；发行版必须使用 HTTPS。不要把密钥传入客户端编译参数。

## 原生推送配置

第一版适配极光推送；没有配置时明确显示不可用，不会把设备显示为已接通。只在用户点击连接或恢复既有连接时初始化 SDK。

服务端环境变量：

```dotenv
JPUSH_APP_KEY=<应用 AppKey>
JPUSH_MASTER_SECRET=<仅保留在服务端>
JPUSH_APNS_PRODUCTION=false
```

客户端：

```sh
flutter run --dart-define=API_BASE_URL=https://bus.su7.space --dart-define=JPUSH_APP_KEY=<同一个AppKey> --dart-define=JPUSH_PRODUCTION=false
```

- 目前包名/Bundle ID 为 `space.su7.xiabanwang`，需与推送项目及签名一致。Android Gradle 从 Dart 编译参数读取 AppKey。
- 服务端按当前登录账号绑定设备，设备标识加密保存；退出前解绑。最多 10 台设备。
- 发送接口的 `accepted`、发送审计中的 `sent` 仅代表推送平台接受，不是手机回执。实际收达用测试通知和真机检查确认。
- 公交消息 TTL 为 60 秒，降低旧提醒延迟抵达的风险。暂不做后台轮询或使用本地闹钟模拟实时公交通知。
- Android 国内厂商离线推送还需配置对应厂商应用与 SDK 通道；当前只有极光基础接入，不能承诺所有手机被杀进程后仍能收到。
- iOS 必须在 macOS/Xcode 中配置开发者团队、Provisioning Profile、Push Notifications，并在极光后台上传对应 APNs 凭据。`Runner.entitlements` 默认开发环境；发布需核对生产 APNs 签名及两端 production 参数。
- `ios/Podfile` 配置 no-IDFA JCore 与通知权限宏。首次 iOS 构建使用 CocoaPods 路径，按 Flutter 环境需要执行 `flutter config --no-enable-swift-package-manager` 后 `flutter pub get`、`pod install`。平台插件本次尚未在 macOS 上编译验证。
- Android 发行构建使用独立 release 签名，通过忽略的 `android/key.properties` 注入。务必备份并复用签名文件以支持覆盖升级。

参考：[极光 Flutter 插件](https://pub.dev/packages/jpush_flutter)、[推送 API](https://docs.jiguang.cn/jpush/server/push/rest_api_v3_push)。

## 验证

```sh
flutter analyze
flutter test
python -m unittest discover -s tool -p test_serve_web.py
flutter build web --dart-define=API_BASE_URL=https://bus.su7.space --dart-define=LOCAL_API_PROXY=true
```

Web/PWA 和 Android ARM64 release APK 已可在本机构建；Dart 分析、自动化测试、浏览器流程与 APK 签名已验证。本机没有连接 Android 真机，也没有 macOS/Xcode；iOS 原生包、后台/锁屏/杀进程通知仍需相应真机环境验证。

## 代码位置

- `lib/api.dart`：HTTP、鉴权续期、错误处理、到站状态判断。
- `lib/push.dart`：手机通知接入与通知跳转。
- `lib/screens/`：登录、通勤首页、创建/编辑、详情、设置。
- `lib/demo.dart`：隔离的预览数据。
- `tool/`：本地 Web 预览服务、预览服务测试和独立组件预览入口。
- `docs/BACKEND.md`：后端依赖、接口兼容性和独立发布说明。

手机端新建提醒统一使用自定义重复：每 1–52 周、选择星期、开始日期、可跳过法定节假日。间隔周规则使用已有后端接口，不需要新增排期字段或能力检查接口。

已移除“全天”，手机端始终提交明确开始、结束时间，不能相同；结束早于开始时表示跨午夜。旧的每天/法定工作日规则在打开编辑时保持原样，只有确认自定义弹层后才替换。多渠道配置和通知模板现已迁入客户端“高级扩展”；用户、城市、邀请码和配额仍由独立 Web 管理后台维护。

`flutter run -d chrome -t tool/repeat_preview.dart` 可单独检查重复弹层，不读取账号或公交数据。

## 多车与地图

整体布局与状态设计见 [DESIGN.md](DESIGN.md)。首页直接展开地图，并以紧凑列表显示车辆；详情页保留更完整的车辆与线路站点信息。

详情页展示同线路、同方向驶向上车站的车辆，默认展开最近三辆，可展开其余车辆。编号与地图联动，点击车辆聚焦它和上车站；手动刷新不会重置地图视野。已经驶过及站数未知的车辆单独列出，不当作下一班。没有坐标仍保留站数，地图失败可重试。

- 地图使用 `flutter_map` 和 OpenStreetMap HTTPS 瓦片，保留可点击署名、原生应用 User-Agent 及默认缓存；不申请手机定位、不做离线下载。正式规模化运营前按 [OSM 瓦片政策](https://operations.osmfoundation.org/policies/tiles/) 选择适合的地图服务；国内网络可用性需真机验证。
- 车来了的车辆坐标使用 WGS-84，原始站点 `lat/lng` 为 BD-09。服务端现在优先返回 `wgsLat/wgsLng`，并附 `coordinateSystem`。客户端对旧车来了服务的站点单独做 BD-09 转 WGS-84 近似转换，避免双重转换或车辆与站点错位。
- 新接口 `distanceSource: target-stop` 的 `distanceMeters` 才表示距上车站；`distanceToSc` 单独保留为 `nextStopDistanceMeters`，不能冒充距上车站。跨上车站共享的缓存也不会借用另一个站的距离。
- 旧接口距离字段有歧义，客户端用车辆和校正后站点的坐标显示“直线约 X 米”，不冒充行驶里程；无坐标且无可信距离时明确显示暂未提供。服务端距离修正需部署后生效，地图和直线距离兼容现有服务。
- 超过两分钟的快照显示“上次位置”，不继续展示实时预计分钟数。`tool/vehicle_preview.dart` 是独立的只读快照校验入口，需要在构建目录放置含 `route`、`realtime` 的 `transit-snapshot.json`，保留原始查询时间，不替换主入口的真实 API。


## 0.2.0：可安装网页版与高级扩展

- 用户主站：<https://bus.su7.space/>。iPhone 使用 Safari 添加到主屏幕，进入“我的 → 开启本机通知”，允许后发送测试。需要 iOS 16.4 或以上。
- Android 安装包与安装说明：<https://bus.su7.space/download.html>。当前发行包为 ARM64，使用独立 release 签名。当前无极光应用凭据，原生通知尚未开通；可使用高级扩展或安装网页版接收 Web Push。
- “我的 → 高级扩展”：支持钉钉、企业微信、飞书自建应用、Telegram、HTTPS Webhook；创建、编辑、启停、删除、测试与自定义模板。编辑凭证留空保留原值，服务器不回传密钥。
- 提醒编辑的“接收渠道”可同时选择多个渠道；未修改接收渠道时不会覆盖原有绑定。
- “我的 → 修改密码”更新账号密码并恢复当前会话。
- 账号与旧提醒全部保留。React 管理后台独立位于 `/admin/`。

通知实现：`lib/push.dart` 按平台选择 `push_native.dart` / `push_web.dart`。浏览器接口在 `web/web-push.js`，后台接收与点击跳转在 `web/sw.js`，保留根 scope 和旧 `/sw.js` 地址。页面恢复不申请权限、不静默转移账号订阅；只有明确点击才连接通知。自建 worker 不缓存 API 或账户数据。

原生发行构建需在忽略的 `android/key.properties` 中提供 `storeFile`、`storePassword`、`keyAlias`、`keyPassword`，签名文件与凭据不得提交 Git。已有本机发布密钥应备份并持续复用，以便覆盖升级。

```sh
flutter analyze
flutter test
node --test tool/web_push.test.mjs
flutter build web --no-web-resources-cdn --no-wasm-dry-run
flutter build apk --release --target-platform android-arm64
```

网页构建使用本地 CanvasKit 资源，减少运行时对第三方 CDN 的依赖。iPhone 的真实锁屏通知仍需用户在设备上授权并验证收达，推送平台接受不等于手机已经收到。
