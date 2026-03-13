# Teleport

[English](README.md) | [简体中文](README.zh-CN.md)

Teleport 是一款原生 macOS 应用，可以伪造 iOS 设备的定位——支持模拟器，以及通过 USB 或 Wi-Fi 连接的实体设备。

基于 SwiftUI 和 MapKit 构建。在地图上点一个位置，按下 Simulate，设备就以为自己在那里。

![Teleport – 定位模拟](Resources/screenshot-main.jpg)

![Teleport – 路线构建](Resources/screenshot-route.jpg)

## 功能

**全面的设备支持** — 同一个应用，支持 iOS 模拟器和通过 USB 或 Wi-Fi 连接的实体 iPhone。

**虚拟摇杆** — 实时移动模拟位置，无需每次重新选点。非常适合在测试时随时调整位置。

**自定义路线** — 在任意停靠点之间绘制直线路径，或通过 Apple 地图导航将路线贴合真实道路。两种模式均支持按固定间隔或目标速度回放，路线的保存、加载和编辑全部支持。

**GPX 导入与导出** — 导入现有路线，或将你的路线导出备用。

其他功能：

- 点击地图任意位置选点，或按名称搜索，或直接输入坐标
- 在应用内保存路线，随时重新加载、重命名、编辑或复制
- 会话控制提供清晰的状态显示，随时可以停止或重置

## 免责声明

Teleport 仅用于开发测试和调试。其他用途风险自负，应用及其开发者对任何后果不承担责任。

## 环境要求

- macOS
- 已安装 Xcode，并至少启动过一次（使 `xcrun`、`simctl` 和 `devicectl` 可用）
- 真机：iPhone 已开启开发者模式，并安装 `python3` 和 `pymobiledevice3`
- Wi-Fi 真机：先通过 USB 配对一次，然后保持设备解锁并连接同一网络

如果 macOS 提示缺少开发者工具：

```sh
xcode-select --install
```

如果 `xcrun` 指向了错误的 Xcode：

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

然后启动一次 Xcode，完成初始化。

安装 Python 依赖：

```sh
python3 -m pip install pymobiledevice3
```

## 开始使用

### 下载

从 [Releases](https://github.com/samuelhe52/Teleport/releases) 下载最新 `.dmg`，将 `Teleport.app` 拖入应用程序文件夹，然后启动。

### 在 Xcode 中运行

1. 打开 `Teleport.xcodeproj`。
2. 选择 `Teleport` scheme。
3. 构建并运行。

### 从命令行构建

```sh
xcodebuild -project Teleport.xcodeproj -scheme Teleport -destination 'platform=macOS' build
```

## 基本用法

1. 启动 Teleport，选择设备。
2. 连接设备。
3. 选择位置——点击地图、搜索，或直接输入坐标。
4. 点击 `Simulate`，完成。
5. 如需模拟移动，可以创建路线。
6. 路线可保存备用，也可导入/导出 GPX 文件。
7. 完成后点击 `Stop`。

真机可能会在首次运行时请求管理员授权、提示安装 Python 依赖，或需要先通过 USB 连接一次才能启用 Wi-Fi 发现。

## 开发

- `make format` 执行 `swift format -r -p -i .`
- `make lint` 执行 `swift format lint -r -p .`

## 说明

Teleport 最初叫做 iOSAnywhere。

如果你在中国大陆使用，Apple 地图搜索通常只返回中国境内的地点，搜索海外地点一般需要 VPN。当然你也可以直接在地图上拖到任意位置手动选点。
