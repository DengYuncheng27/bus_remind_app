# 后端对接与独立发布

本客户端从 [BusReminder](https://github.com/DengYuncheng27/BusReminder) 的本地 `mobile/` 工程拆出，Android、iOS、Web 预览共用 Dart 代码。后端继续使用 Node.js、Fastify 和 SQLite，React 网页管理端也留在后端仓库。

## 职责边界

| 客户端仓库 | 后端仓库 |
| --- | --- |
| 登录界面、会话安全存储 | 账号认证、权限与会话续期 |
| 地图、车辆位置、方向与上车站选择 | 公交上游接入、缓存、坐标与距离字段 |
| 提醒规则编辑、启停操作 | 规则校验、数据库、节假日日历与提醒调度 |
| 原生推送注册、权限和通知跳转 | 设备绑定、推送发送与服务端密钥 |

客户端通过 `API_BASE_URL` 编译参数指定 HTTPS API，默认 `https://bus.su7.space`。身份通过 Bearer Token 传递；服务端可用 `X-Session-Token` 响应头续期。账号凭据和通知设备标识不进入版本库。

## 接口兼容

| 功能 | 接口或约定 |
| --- | --- |
| 登录与账号 | `/api/auth/*`、`/api/me` |
| 公交与换向 | `/api/cities`、`/api/routes/search`、`/api/routes/:lineId`、`/api/routes/:lineId/realtime` |
| 提醒与渠道 | `/api/reminders`、`/api/reminders/:id`、`/api/channels` |
| 今天暂停 | `POST /api/reminders/:id/pause-today`；旧服务不存在时明确提示失败 |
| 原生推送 | 需要部署后端手机推送接口、配置极光与 APNs，并完成真机验证；客户端调用见 `lib/push.dart` |

普通自定义规则、旧规则编辑和车辆查询可使用已有接口。新功能是否可用取决于实际部署的后端版本，而非客户端仓库是否包含界面。

浏览器直接访问 API 时，后端 CORS 应允许 GET、HEAD、POST、PATCH、DELETE，接受 Authorization/Content-Type 并暴露 X-Session-Token。本地预览可显式启用 `LOCAL_API_PROXY=true`，仅在 `127.0.0.1:8765` 将 `/api/` 转发到固定线上服务；这是开发预览工具，不是生产部署服务。

## 发布顺序

涉及新 API 或数据库字段时先更新、验证后端，再发布使用新能力的客户端。客户端的 UI 调整和兼容旧接口的功能可以独立发布。后端构建及测试在后端仓库运行，本仓库只运行 Flutter 和预览工具的检查。

本次拆分保留客户端包名 `space.su7.xiabanwang` 与登录存储键。仓库名变化不修改既有账号、提醒或推送配置。
