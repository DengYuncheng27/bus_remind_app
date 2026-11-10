# Flutter 分支、PR 与 Web 自动部署

## 日常流程

从更新后的 `origin/main` 创建 `codex/<任务名>` 分支，开发并验证后推送，创建 GitHub PR。检查稳定的 `CI` 通过、自审差异后使用 Squash merge；远程分支自动删除。单人维护无需长期 develop 分支或第二人审批。

main 的服务端保护要求 PR、`CI` 成功、分支与 main 同步，禁止直接推送、force push 和删除 main。管理员也受保护。启用本地补充保护：`git config core.hooksPath .githooks`。

当前工作区有其他会话改动时使用独立 worktree；不要自动提交 README、日志或无关文件。开发分支只检查，不发布。

## 检查与部署范围

| 修改 | 日常检查 | 合并 main 后 Web 部署 |
| --- | --- | --- |
| lib、assets、pubspec、web | Flutter 分析/测试、Web JS/Python 检查、Web 构建 | 是 |
| Web CD 工作流、ci_plan.py、web_release.py | 同上 | 是 |
| 仅 test、analysis_options、Android/iOS 工程 | Flutter 分析/测试 | 否 |
| 仅 Android 发布工具、其他 tool 工具 | 相应工具检查 | 否 |
| 纯 Markdown 文档 | CI 轻量检查 | 否 |

原生专属修改仍按影响面做原生验证，不能把 Flutter 分析通过当成 APK/iOS 构建通过。Android 正式发版继续由明确的版本 tag 触发，沿用原签名、版本递增和 GitHub Releases 下载校验。

## Web 发布

`.github/workflows/ci.yml` 构建 release Web，明确连接 `https://bus.su7.space`，使用本地 CanvasKit。`tool/web_release.py` 将同一次构建的 `build/web/` 打包为只包含 `client/` 文件的 `client.tar.gz`，记录 commit、大小和 SHA-256；部署任务下载同一产物，不重新编译。

仅已合并到本仓库 main 的 PR 可以触发 Web 部署。部署前核对 main 仍是本次 SHA，并要求新客户端源码是当前线上客户端 commit 的后代；过期运行跳过。失败可重跑最新 main 的任务，已部署相同客户端 commit 时校验后幂等返回。

后端服务器的专用入口 `cd-host.py --component clientWeb` 在同一把部署锁下：

1. 校验上传类型、大小、哈希和部署前观察的线上 commit/发布目录。
2. 核对线上后端与管理后台的文件集合和哈希，复用这些原产物、原 revision，以及线上后端 Git bundle。
3. 组成现有部署脚本要求的组合包，备份数据库/环境，在禁用提醒 worker 的副本实例验证。
4. 切换并验证；失败恢复代码和环境，保留数据库备份，不覆盖新增业务数据。

这仍是组合部署，会短暂重启后端；不宣称已实现独立静态资源切换。后端仓库自己的 CD 则反向复用线上客户端。两个仓库的 GitHub 并发组并不共享，因此依靠服务器同一把锁和发布路径校验避免互相覆盖；快照过期时拒绝发布，重新评估后重跑最新 main。

## 凭据与记录

GitHub Secrets：`CD_SSH_PRIVATE_KEY`、`CD_SSH_KNOWN_HOSTS`。Variables：`CD_SSH_HOST`、`CD_SSH_PORT`、`CD_SSH_USER`。此私钥与后端不同，服务器强制限定为客户端产物；不得上传后端文件、使用交互 shell 或任意命令。

PR 和普通分支无部署凭据。严禁关闭主机公钥校验、把秘密放进 Dart 编译参数或 Git、从历史聊天/session 找密码。安装/升级 root 所有的服务器入口需要单独审查，不由客户端产物自动替换。

GitHub 产物保留 14 天。成功部署在服务器记录 `deployment.json`、`release-manifest.json`，包含后端、管理后台和客户端各自 commit 与产物哈希。以 `Deploy Web production` 和服务器记录确认上线，不把“PR 合并”当作“已部署”。

跨仓库 API 改动先合并并部署兼容后端，再合并客户端 PR。APK 仍只通过 GitHub Releases 分发，不因 Web 发布修改 Android 签名或提供应用内自动更新。
