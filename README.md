# LongScreenshot MVP

## 中文

LongScreenshot 是一个适合普通 Apple ID / 免费账号路径的 iOS 长截图 MVP。它不依赖付费 Apple Developer Program，也不包含 ReplayKit 录屏扩展。当前版本的目标是：在云端 macOS runner 构建出可下载的 unsigned IPA，然后在 Windows 上用 Sideloadly、AltStore 或 SideStore 重新签名并安装到 iPhone。

### 功能

- 从 iPhone 相册手动选择多张截图。
- 按选择顺序上传截图到云端拼接服务。
- 云端 FastAPI / OpenCV 服务返回拼接后的长图。
- iOS App 将返回的长图保存到系统相册。
- Codemagic workflow 生成 `LongScreenshot-unsigned.ipa` artifact。

### 当前限制

- 这个免费账号 MVP 不包含控制中心里的 ReplayKit Broadcast Upload Extension。
- CI 产出的 IPA 是 unsigned，不能直接安装到 iPhone。
- 必须用 Sideloadly、AltStore 或 SideStore 等工具重新签名安装。
- 免费 Apple ID 签名通常会过期，需要定期重新签名。
- `127.0.0.1` 在 iPhone 上表示 iPhone 自己；连接 Windows 上运行的拼接服务时，请使用 Windows 的局域网 IP。

### 项目结构

- `cloud/`：Python FastAPI 长图拼接服务。
- `ios/`：SwiftUI iOS App 和共享 Swift 工具。
- `codemagic.yaml`：云端 macOS 构建与 unsigned IPA 打包 workflow。

### 本地运行云端拼接服务

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

1. 准备 2-5 张有重叠区域的截图。
2. 打开 LongScreenshot。
3. 输入 iPhone 能访问到的拼接服务地址，例如 `http://<你的Windows局域网IP>:8000/stitch`。
4. 按从上到下的顺序选择截图。
5. 点击导入截图。
6. 授权保存到相册。
7. 上传并保存长图。

## English

LongScreenshot is an iOS long-screenshot MVP designed for the normal Apple ID / free-account sideloading path. It does not require a paid Apple Developer Program account and does not include a ReplayKit recording extension. The current goal is to build an unsigned IPA on a cloud macOS runner, then re-sign and install it from Windows with Sideloadly, AltStore, or SideStore.

### Features

- Manually select multiple screenshots from the iPhone photo library.
- Upload selected screenshots to the cloud stitcher in selection order.
- Receive a stitched long image from the FastAPI / OpenCV cloud service.
- Save the returned long image to the system photo library.
- Generate a `LongScreenshot-unsigned.ipa` artifact with Codemagic.

### Current limitations

- This free-account MVP does not include a Control Center ReplayKit Broadcast Upload Extension.
- The IPA produced by CI is unsigned and cannot be installed directly on an iPhone.
- A sideloading tool such as Sideloadly, AltStore, or SideStore must re-sign and install the IPA.
- Free Apple ID signing usually expires and must be refreshed regularly.
- `127.0.0.1` on an iPhone points to the iPhone itself. Use the Windows machine's LAN IP when connecting to a stitcher running on Windows.

### Project structure

- `cloud/`: Python FastAPI stitching service.
- `ios/`: SwiftUI iOS app and shared Swift utilities.
- `codemagic.yaml`: Cloud macOS build and unsigned IPA packaging workflow.

### Run the cloud stitcher locally

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

1. Prepare 2-5 overlapping screenshots.
2. Open LongScreenshot.
3. Enter a stitch endpoint URL reachable from the iPhone, for example `http://<your-windows-lan-ip>:8000/stitch`.
4. Choose screenshots in top-to-bottom order.
5. Import the screenshots.
6. Grant photo save permission.
7. Upload and save the long image.
