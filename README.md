# LongScreenshot MVP

## 中文

LongScreenshot 是一个适合普通 Apple ID / 免费账号路径的 iOS 长截图 MVP。当前可用主路径仍然是手动导入截图并在 iPhone 本地拼接；同时包含一个实验性、最小化的 ReplayKit 控制中心录屏入口，仅用于验证系统目标发现和启动。当前版本的目标是：在云端 macOS runner 构建出可下载的 unsigned IPA，然后在 Windows 上用 Sideloadly、AltStore 或 SideStore 重新签名并安装到 iPhone。

### 功能

- 从 iPhone 相册手动选择多张截图。
- 按选择顺序在 iPhone 本地拼接截图。
- 实验性 ReplayKit 控制中心录屏入口，用于验证“长截图录屏”能否出现在系统录屏目标中。
- iOS App 将生成的长图保存到系统相册。
- Codemagic workflow 生成 `LongScreenshot-unsigned.ipa` artifact。
- Python FastAPI / OpenCV 服务保留为可选的开发和参考工具。

### 当前限制

- ReplayKit 控制中心录屏入口仍是实验功能：当前只验证入口和启动，不会在录屏结束后自动生成长截图。
- 免费 Apple ID / sideload 工具可能无法正确注册或签名录屏扩展；如果控制中心看不到“长截图录屏”，可能需要付费 Apple Developer 账号路径。
- CI 产出的 IPA 是 unsigned，不能直接安装到 iPhone。
- 必须用 Sideloadly、AltStore 或 SideStore 等工具重新签名安装。
- 免费 Apple ID 签名通常会过期，需要定期重新签名。
- Python 云端拼接服务仅作为可选的开发、旧版兼容和参考工具；iPhone 正常使用不需要服务器。

### 项目结构

- `cloud/`：Python FastAPI 长图拼接服务。
- `ios/`：SwiftUI iOS App 和共享 Swift 工具。
- `codemagic.yaml`：云端 macOS 构建与 unsigned IPA 打包 workflow。

### 可选：本地运行云端拼接服务

```bash
cd cloud
python -m venv .venv
. .venv/Scripts/activate
python -m pip install -e '.[test]'
pytest -q
uvicorn longshot_stitcher.api:app --host 0.0.0.0 --port 8000
```

macOS / Linux shell 激活虚拟环境时使用：

```bash
. .venv/bin/activate
```

以下命令仅用于可选开发和参考场景，不是 iPhone App 正常使用流程的一部分。

健康检查：

```bash
curl http://127.0.0.1:8000/health
```

期望返回：

```json
{"status":"ok"}
```

### 构建 IPA

1. 将仓库推送到 GitHub。
2. 在 Codemagic 连接这个仓库。
3. 运行 `ios-free-sideload` workflow。
4. 从 Codemagic artifacts 下载 `LongScreenshot-unsigned.ipa`。
5. 在 Windows 上使用 Sideloadly、AltStore 或 SideStore，用普通 Apple ID 重新签名并安装到 iPhone。

### iPhone 使用流程

1. 用 Codemagic 生成 `LongScreenshot-unsigned.ipa`。
2. 在 Windows 上用 Sideloadly、AltStore 或 SideStore 重新签名并安装到 iPhone。
3. 打开 App，点击“导入截图”，按从上到下的顺序选择 2 到 8 张有重叠区域的截图。
4. 导入后在界面预览截图顺序；可继续点击“导入截图”追加图片，也可点缩略图右上角的叉删除图片。
5. 点击“拼接保存”，按提示授权保存到相册。
6. 如果截图宽度不一致，App 会提示是否按第一张截图宽度等比缩放后继续拼接。
7. 生成的长截图会保存到系统相册。
8. 可选验证：长按控制中心的屏幕录制按钮，查看录屏目标中是否出现“长截图录屏”；该实验入口目前不会在录屏结束后自动生成长截图。

当前版本已经改为 iPhone 本地拼接，不需要配置服务器 URL，也不需要在 Windows 上运行云端拼接服务。

## English

LongScreenshot is an iOS long-screenshot MVP designed for the normal Apple ID / free-account sideloading path. The current usable path remains manual screenshot import and local stitching on the iPhone, with an experimental/minimal ReplayKit Control Center entry-point included only for discovery and startup validation. The current goal is to build an unsigned IPA on a cloud macOS runner, then re-sign and install it from Windows with Sideloadly, AltStore, or SideStore.

### Features

- Manually select multiple screenshots from the iPhone photo library.
- Stitch screenshots locally on the iPhone in selection order.
- Include an experimental ReplayKit Control Center recording entry-point to test whether “长截图录屏” appears as a system recording target.
- Save the generated long image to the system photo library.
- Generate a `LongScreenshot-unsigned.ipa` artifact with Codemagic.
- Keep the Python FastAPI / OpenCV service as optional developer and reference tooling.

### Current limitations

- The ReplayKit Control Center recording path is experimental: this phase only validates extension discovery and startup, and does not automatically generate a long screenshot after recording.
- Free Apple ID / sideloading tools may not correctly sign or register the broadcast extension; if Control Center does not show “长截图录屏”, the feature may require a paid Apple Developer account path.
- The IPA produced by CI is unsigned and cannot be installed directly on an iPhone.
- A sideloading tool such as Sideloadly, AltStore, or SideStore must re-sign and install the IPA.
- Free Apple ID signing usually expires and must be refreshed regularly.
- The Python cloud stitcher is optional developer, legacy compatibility, and reference tooling; normal iPhone use does not require a server.

### Project structure

- `cloud/`: Python FastAPI stitching service.
- `ios/`: SwiftUI iOS app and shared Swift utilities.
- `codemagic.yaml`: Cloud macOS build and unsigned IPA packaging workflow.

### Optional: run the cloud stitcher locally

```bash
cd cloud
python -m venv .venv
. .venv/Scripts/activate
python -m pip install -e '.[test]'
pytest -q
uvicorn longshot_stitcher.api:app --host 0.0.0.0 --port 8000
```

On macOS / Linux shells, activate the virtual environment with:

```bash
. .venv/bin/activate
```

The following commands are only for optional developer and reference scenarios; they are not part of the normal iPhone app usage flow.

Health check:

```bash
curl http://127.0.0.1:8000/health
```

Expected response:

```json
{"status":"ok"}
```

### Build the IPA

1. Push this repository to GitHub.
2. Connect the repository to Codemagic.
3. Run the `ios-free-sideload` workflow.
4. Download `LongScreenshot-unsigned.ipa` from Codemagic artifacts.
5. Re-sign and install it from Windows using Sideloadly, AltStore, or SideStore with a normal Apple ID.

### iPhone usage flow

1. Build `LongScreenshot-unsigned.ipa` with Codemagic.
2. Re-sign and install it on the iPhone from Windows with Sideloadly, AltStore, or SideStore.
3. Open the app, tap “导入截图”, and choose 2 to 8 overlapping screenshots in top-to-bottom order.
4. Preview the imported screenshot order in the app; tap “导入截图” again to append images, or tap the x button on a thumbnail to remove it.
5. Tap “拼接保存” and grant photo save permission when prompted.
6. If screenshot widths differ, the app asks whether to resize other images to the first screenshot width before continuing.
7. The generated long screenshot is saved to Photos.
8. Optional verification: long-press the Control Center screen recording button and check whether “长截图录屏” appears as a recording target; this experimental entry-point does not yet auto-generate long screenshots after recording.

The current iPhone app stitches locally on-device. It does not require a server URL or a Windows-hosted stitching service.
