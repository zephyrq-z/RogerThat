# RogerThat

<sub>[English](README.md) · 简体中文</sub>

按 ⌘C 之后，剪贴板真的变了才会浮出一颗 22pt 高的微信绿小胶囊 —— 不用再怀疑自己是不是没复制上，也不用按第二遍。

![preview](docs/preview.png)

需要 macOS 13+。菜单栏 App，约 250 行 Swift，无第三方依赖，零权限。

## 为什么做

⌘C 是静音的。目标 App 吃掉这个按键，或者你框错了选区，都要等到下一次粘贴才发现。RogerThat 直接盯剪贴板：只有内容真的上去了，才给你一个安静的“Copied”。

## 安装

1. 到 [Releases](../../releases) 下载 `RogerThat-1.0.0.zip` 并解压。
2. 把 `RogerThat.app` 拖进 `/Applications`。
3. 首次打开：构建是 ad-hoc 签名、未公证，macOS 会拦一下 —— 右键点 App → **打开**，或执行

   ```sh
   xattr -dr com.apple.quarantine /Applications/RogerThat.app
   ```

## 使用

每次启动都会弹出设置窗，所以即使菜单栏图标藏起来了，你也知道它活着。

| 开关 | 作用 |
| --- | --- |
| Show notification | 提示总开关 |
| Show copied text | 附带被复制内容的前 40 个字符（默认关闭，见下方隐私说明） |
| Show menu bar icon | 显示或隐藏菜单栏图标；菜单里可以再打开设置 |

## 实现原理

每 0.15s 读一次 `NSPasteboard.general.changeCount`。计数器变了，说明剪贴板顶部真的换了内容，于是光标旁浮出胶囊，1.1s 后淡出。不监听键盘，不需要辅助功能，也不需要输入监控。

两个必须说清楚的副作用：

- 它对**任何**写入剪贴板的动作都有反应，不只是 ⌘C：截图到剪贴板、别的 App 写的、菜单栏的“编辑 → 拷贝”都会触发。这正是“我复制上了吗”的诚实答案；如果你要的严格是“我按了 ⌘C”，那得开输入监控，代价更大且答案更差。
- 打开 **Show copied text** 后，App 会读剪贴板内容。Apple 已预告“程序化读通用粘贴板会弹系统提示”（macOS 15.4 起以开发者开关预览）。只读计数器可以永远避开这个变化，所以内容预览默认关闭。

## 从源码构建

只需要 Command Line Tools，不需要 Xcode 工程。

```sh
./build.sh
open dist/RogerThat.app
```

`--selftest` 用私有粘贴板验证变化检测逻辑（不会碰你正在用的剪贴板）。

## 许可

MIT