# LongScreenshot 排错记录

本文件用于记录本项目开发和 Codemagic 打包过程中遇到的问题、根因、解决方案和验证结果。

## 维护规则

- 新错误先记录现象、日志、触发步骤。
- 修复后补充根因、改动位置、验证命令和结果。
- Claude Code 已配置本地 hook：以后 Bash 工具执行失败时，会自动把失败命令和错误输出追加到本文件末尾的“自动捕获的错误日志”。
- 如果 hook 是在当前会话中新建的但没有立刻触发，打开 `/hooks` 或重启 Claude Code 以重新加载配置。
- 自动捕获的日志只记录原始失败信息；最终解决方案仍需要在排查完成后整理到“已解决问题”。

## 已解决问题

### 1. WebSearch 查询 LiveContainer 信息耗时过长

- 现象：早期可行性调研中 WebSearch 等待时间很长。
- 根因：外部搜索请求超时或响应慢；并且 LiveContainer / iOS Extension 兼容性结论本可以更快通过平台限制判断得出。
- 解决方案：后续对明确的 iOS 原生能力限制优先基于平台机制判断，只有需要最新事实时再使用 WebSearch。
- 验证：架构决策已改为免费账号可行的单 App 手动导入方案。

### 2. LiveContainer 不适合 ReplayKit Broadcast Upload Extension

- 现象：最初希望用 LiveContainer 续签或运行带录屏扩展的 App。
- 根因：ReplayKit Broadcast Upload Extension 必须被 iOS / SpringBoard 识别为真实 app extension，并具备正确 entitlements；LiveContainer guest app 不能可靠注册这种系统扩展。
- 解决方案：放弃免费账号下的控制中心录屏扩展目标，改成单 App + 手动截图导入 + 云端拼接 + sideload IPA。
- 验证：新设计文档和实现均不再包含 ReplayKit extension、App Groups 或付费开发者签名。

### 3. 云端 API 对损坏图片返回 500

- 现象：上传损坏或截断图片时，FastAPI 可能返回 HTTP 500。
- 根因：Pillow 解码时除了 `UnidentifiedImageError`，还可能抛出 `OSError` 或 `ValueError`。
- 解决方案：在 `cloud/src/longshot_stitcher/api.py` 中捕获 `(UnidentifiedImageError, OSError, ValueError)`，统一返回 HTTP 400。
- 验证：`cloud/tests/test_api.py` 增加损坏图片测试；`pytest -q` 通过。

### 4. 手动导入 session ID 可能碰撞

- 现象：`ImageImportStore` 最初只用秒级时间戳生成 session ID。
- 根因：同一秒内连续导入会产生相同 session ID，可能覆盖同一目录。
- 解决方案：在时间戳后追加 `UUID().uuidString`。
- 验证：代码审查通过；导入目录名不再只依赖时间戳。

### 5. iPhone 访问 Windows 本地服务容易填错地址

- 现象：默认 `127.0.0.1:8000` 在 iPhone 上不可访问 Windows 服务。
- 根因：`127.0.0.1` 对 iPhone 来说是手机自身，不是 Windows 电脑。
- 解决方案：App UI 和 README 提示使用 Windows 的局域网 IP，例如 `http://<Windows局域网IP>:8000/stitch`。
- 验证：README 中英文说明已记录该限制。

### 6. iOS App 访问局域网 HTTP 可能被 ATS 阻止

- 现象：iPhone App 访问局域网 HTTP 拼接服务可能失败。
- 根因：iOS App Transport Security 默认限制明文 HTTP。
- 解决方案：在 `ios/LongScreenshotApp/Info.plist` 添加 `NSAppTransportSecurity` / `NSAllowsLocalNetworking`。
- 验证：代码审查确认本地 HTTP 场景已覆盖。

### 7. 上传失败后 session 卡在 uploading，无法重试

- 现象：如果上传或保存失败，session 状态会停留在 `.uploading`，UI 只处理 `.ready`，导致无法再次尝试。
- 根因：错误路径没有持久化失败状态，也没有把 `.failed` 纳入可重试列表。
- 解决方案：失败时保存 `.failed` 和 `failureReason`；处理逻辑允许选择 `.ready` 或 `.failed` session 重试。
- 验证：代码审查确认失败后可重试。

### 8. Codemagic 第一次失败：LongScreenshotShared scheme 没有 test action

- 现象：Codemagic 日志显示：

```text
xcodebuild: error: Scheme LongScreenshotShared is not currently configured for the test action.
```

- 根因：XcodeGen 自动生成的 `LongScreenshotShared` scheme 没有关联 `LongScreenshotSharedTests`。
- 解决方案：在 `ios/project.yml` 显式添加 schemes：
  - `LongScreenshotShared` build `LongScreenshotShared`，test `LongScreenshotSharedTests`
  - `LongScreenshotApp` build `LongScreenshotApp`
- 提交：`8550d1e fix: configure shared test scheme`
- 验证：
  - `pytest -q`：`8 passed`
  - 远程 `main` 更新到 `8550d1e`

### 9. Codemagic 第二次失败：找不到 iPhone 16 simulator

- 现象：Codemagic 日志显示：

```text
xcodebuild: error: Unable to find a device matching the provided destination specifier:
{ platform:iOS Simulator, OS:latest, name:iPhone 16 }
```

- 根因：Codemagic 当前 Xcode 镜像没有名为 `iPhone 16` 的可用 simulator，只暴露了 `Any iOS Simulator Device` 等占位 destination。
- 解决方案：修改 `codemagic.yaml`，不再写死 `name=iPhone 16`，而是：
  1. 读取当前可用 iOS simulator runtime。
  2. 优先选择可用的 iPhone 16 / 15 / 14 / 13 device type。
  3. 用 `xcrun simctl create LongScreenshotTestSimulator` 创建临时 simulator。
  4. 用 `xcodebuild test -destination "id=$SIM_UDID"` 跑测试。
  5. 通过 `trap` 自动删除临时 simulator 和 JSON 文件。
- 提交：`bae906d fix: create simulator for ci tests`
- 验证：
  - `bash -n` 校验提取出的 CI shell 片段通过。
  - `pytest -q`：`8 passed in 0.93s`
  - 远程 `main` 更新到 `bae906d97ce70cfc9bcfd27f592f5ee7ac562713`

### 10. 自动维护 hook 初次验证时记录不完整

- 现象：验证 `PostToolUseFailure` hook 时，`jq` 命令不可用，触发了一次 Bash 失败；首次 hook 记录只保存了 JSON 解析错误，缺少原始 stdin。
- 根因：本机 shell 环境没有安装 `jq`；同时 `record_failure.py` 最初直接 `json.load(sys.stdin)`，解析失败后没有保留原始输入。
- 解决方案：改用 Python 校验 settings JSON；更新 `record_failure.py`，先读取 raw stdin，再尝试 `json.loads`，解析失败时把 `raw_stdin` 一并写入日志。
- 验证：使用合成 hook stdin 进行 pipe-test，确认成功命令不会写日志、失败命令会写日志；使用 Python 校验 settings 中存在 `PostToolUse` / `PostToolUseFailure` 的 `Bash` hook。当前会话如未立即触发，需要通过 `/hooks` 或重启 Claude Code 重新加载配置。

## 待继续观察

### Codemagic unsigned IPA 打包

- 当前状态：已修复前两轮 Codemagic 测试阶段失败。
- 下一步：重新运行 `main` / `ios-free-sideload` workflow。
- 成功标准：Codemagic artifacts 中出现 `LongScreenshot-unsigned.ipa`。
- 如果继续失败：把完整日志加入本文件，并按“现象 → 根因 → 解决方案 → 验证”格式维护。

## 自动捕获的错误日志

下面的条目由 Claude Code 本地 hook 自动追加。整理后的最终结论应移动或复制到“已解决问题”。
