# Lyra · 天琴座

原生 macOS 键盘与鼠标音效工具，用 Swift / AppKit 编写。声音在本机播放，**不联网，不上传数据，不保存按键记录**。

## 功能

- **键盘音效**：14 套内置音色，包括机械键盘、泡泡、橡皮鸭、街机和猫叫，支持按下与松开音效。
- **鼠标音效**：支持左键、右键和中键，可独立选择音色、调节音量和试听。
- **打字伴奏**：打字时播放音乐，长按按键持续播放，松开最后一个按键 2 秒后暂停，下次打字从原位置继续。目前内置贝多芬《第五交响曲》开篇 60 秒，循环播放。
- **菜单栏控制**：支持登录时自动启动，按 `Ctrl + Option + M` 随时静音。

## 实现原理

Lyra 通过 Core Graphics 的只读事件监听（`CGEventTap` / `listenOnly`）接收物理键码、按下与松开状态，不拦截或修改输入。鼠标音效开启后，会额外监听左、右、中键，不读取指针位置。

键盘和鼠标的音效来自应用内置的 WAV 文件。程序按键码找到对应的声音片段，由 `AVAudioEngine` 在本机播放；两路音效分别管理音色和音量。普通键音会忽略长按产生的自动重复事件。

打字伴奏使用 `AVAudioPlayer` 播放连续录音。程序只在内存中维护当前按住的键和暂停计时，暂停时保留播放位置。退出应用后不保存播放进度。

核心代码位于 [main.swift](Sources/main.swift)、[InputRouting.swift](Sources/InputRouting.swift) 和 [TypingMusicPlayer.swift](Sources/TypingMusicPlayer.swift)。

## 隐私与离线运行

Lyra 没有账号、遥测、自动更新或在线下载功能，所有音频均随应用提供。输入监听只用于触发声音，不读取输入的字符文本、剪贴板或窗口内容，也不保存按键历史。音色、音量等偏好通过 `UserDefaults` 保存在本机。

禁网规则在输入监听启动前生效：[OfflineGate.c](Sources/OfflineGate.c) 使用 macOS Seatbelt 拒绝本进程的网络访问，并禁止创建或执行子进程。**如果规则无法启用，应用会直接退出。** 构建脚本会验证 IPv4 / IPv6 的 TCP、UDP 和 socket 绑定操作确实被系统拒绝。

全局音效需要“输入监控”权限，不需要“辅助功能”权限。Seatbelt 使用的 `sandbox_init` 接口已被 Apple 弃用，后续系统兼容性需要持续验证；它限制的是 Lyra 进程，不是整台电脑的网络。

## 构建与使用

当前版本要求 macOS 26 或更新版本，以及 Xcode Command Line Tools。依赖系统自带框架，源码与音频准备好后可离线构建：

```sh
bash build.sh
```

生成的应用位于上级目录 `Lyra.app`。脚本同时检查代码签名、音频素材、鼠标事件映射、伴奏播放逻辑和禁网规则。详细验证记录见 [VERIFICATION.txt](VERIFICATION.txt)。

将应用放入“应用程序”目录并打开，在 **系统设置 → 隐私与安全性 → 输入监控** 中启用 Lyra，然后退出并重新打开。未授权时也可以使用试听。关闭窗口后，应用继续在菜单栏运行。

当前构建使用本地 ad-hoc 签名，尚未经过 Apple 公证。

## 许可与音频来源

代码采用 [MIT 许可证](LICENSE.txt)。音频来源及各自许可如下：

- 10 套机械键音来自 Mechvibes v3.5.7，保留其 [MIT 许可证](Resources/Mechvibes-LICENSE.txt)。Lyra 不是 Mechvibes 官方版本。
- 泡泡、橡皮鸭、街机音效由项目内脚本合成。
- 猫叫来自 qubodup / Jofae 的 CC0 录音，见 [来源说明](Resources/Cat-SOURCE.txt)。
- 交响乐录音由 Skidmore College Orchestra 演奏，经 Musopen 提供，见 [来源与授权说明](Resources/Orchestra-SOURCE.txt)。
