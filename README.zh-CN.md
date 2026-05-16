<p align="center">
  <img src="docs/icon.png" width="180" alt="WeChat Multi 图标" />
</p>

# WeChat Multi

> 在 macOS 上同时运行多个微信账号 —— 只需菜单栏一个图标。

[English](README.md) | **简体中文**

![platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![swift](https://img.shields.io/badge/swift-5.7%2B-orange)
![license](https://img.shields.io/badge/license-MIT-green)

Mac 版微信限制每次只能启动一个实例,第二次启动的进程会被它自己悄悄杀掉。
**WeChat Multi** 通过把 `/Applications/WeChat.app` 克隆成多份、每份赋予
独立的 `CFBundleIdentifier`,绕过了这一限制。每个克隆都拥有独立的沙盒
容器,所以 macOS 会把它当作一个全新的应用,微信本身的"已经在运行"
检测也就失效了。

最终效果:你可以同时登录任意多个微信账号 —— 工作号、生活号、两个手机
号、一个小号 —— 每个都在独立的窗口里运行,关机后状态也能保留。

## 菜单长这样

```
 💬 WC 2                                            ⏰ 9:41
 ┌──────────────────────────────────────┐
 │ 当前运行 2 个微信实例                │
 ├──────────────────────────────────────┤
 │ 启动新实例                       ⌘N  │
 ├──────────────────────────────────────┤
 │ 运行中                               │
 │ 主账号 — PID 34810                 › │
 │ 工作 (Slot 1) — PID 40853          › │
 │ 退出所有实例                     ⌘K  │
 ├──────────────────────────────────────┤
 │ 选择 WeChat.app 位置…                │
 │   ↳ /Applications/WeChat.app         │
 │ 打开克隆目录                         │
 │ 重置所有克隆 (1)…                    │
 ├──────────────────────────────────────┤
 │ 关于 WeChat Multi                    │
 │ 退出 WeChat Multi                ⌘Q  │
 └──────────────────────────────────────┘
```

每个正在运行的实例都可以展开二级菜单,提供 **置于最前**、**退出该实例**
和 **重命名…** 等操作。

## 下载

不想自己编译?直接到 [最新 Release 页面](https://github.com/ashinno/wechat-multi/releases/latest)
下载 `.zip`,解压后拖到 `/Applications` 文件夹双击即可。由于使用 ad-hoc
签名(没有 Apple 开发者证书签名),首次打开时 macOS 可能会提示拒绝,
请 **右键 → 打开** 一次绕过 Gatekeeper。

## 功能

- 🍎 **原生菜单栏应用** —— 不占 Dock、不用 Electron,二进制只有约 190 KB
- ⚡ **一键启动** 一个独立的微信实例
- 🏷️ **自定义名称** 给每个实例起名(如"工作"、"小号"),Cmd+Tab
  和 Dock 都会显示新名字
- 🎨 **彩色标记** 每个克隆在菜单里都有独立的颜色圆点,一眼就能区分
- 🚀 **开机自启动** 偏好设置里勾选即可,基于 `SMAppService`,无需辅助应用
- 📊 **首次克隆进度面板** 在拷贝 + 签名的几秒钟里显示当前步骤,
  不再让你怀疑应用是不是卡死了
- 🔄 **微信升级检测** 自动发现已升级的 `/Applications/WeChat.app`,
  并提示一键刷新所有过期克隆
- 📋 **运行实例列表** 显示进程 PID 和启动时间
- 🪟 **窗口管理** 切换某个实例到前台、退出单个实例、或一键退出全部
- 🔍 **自动定位** WeChat.app 位置,找不到时支持手动选择
- 🖥️ **通用二进制(arm64 + x86_64)**,ad-hoc 签名,无第三方依赖

## 系统要求

- macOS 13 Ventura 或更新版本(自动启动依赖 `SMAppService`)
- 已在 `/Applications/WeChat.app` 安装官方微信
- Xcode Command Line Tools(`xcode-select --install`) —— 仅编译时需要

## 安装

```bash
git clone https://github.com/ashinno/wechat-multi.git
cd wechat-multi
./install.sh
```

`install.sh` 会在需要时自动运行 `build.sh`,把应用拷贝到
`/Applications/WeChat Multi.app` 并启动。首次启动会弹出一个提示窗口
告诉你菜单栏图标的位置 —— 在屏幕右上角找 **WC** 字样。

只编译不安装:

```bash
./build.sh
open "dist/WeChat Multi.app"
```

## 使用

1. 点击菜单栏的 **WC** 图标
2. 选择 **启动新实例**(⌘N)
   - 首次创建某个槽位会花几秒钟克隆 WeChat.app —— APFS 系统的
     copy-on-write 让这一步几乎是瞬时的
   - 一个全新的微信窗口会弹出,等待你登录
3. 想开几个就重复几次。槽位编号是无上限的
4. 想给某个实例起个名字?在它的二级菜单选 **重命名…**,起个
   "工作"、"生活"之类的名字就好
5. 主菜单顶部如果出现 **⚠️ N 个克隆已过期** 警告,说明微信刚刚
   升级过 —— 点 **刷新过期克隆** 把它们重建,登录状态会保留

原版 `/Applications/WeChat.app` 不受任何影响。你仍然可以从 Dock、
Launchpad 或 Spotlight 正常打开它 —— 在我们的菜单里它会显示为
"主账号"。

### 微信升级以后

微信会通过 Sparkle 自动更新原版应用,但是它不会更新你的克隆。
WeChat Multi 会自动检测两者的版本差异,在菜单顶部显示
**⚠️ N 个克隆已过期**,点 **刷新过期克隆** 即可一键重建。

每个账号的数据(登录信息、聊天记录)存放在
`~/Library/Containers/com.wechatmulti.cloneN/` 沙盒容器中,刷新
克隆只会替换应用二进制本身,沙盒数据保持不变,登录状态不会丢失。

如果你想彻底重置某个账号:

```bash
# 先在菜单里退出所有实例,然后:
rm -rf "$HOME/Applications/WeChat Multi"
rm -rf "$HOME/Library/Containers/com.wechatmulti.clone"*
```

## 工作原理

对于每个槽位 *N*,WeChat Multi 会:

1. `cp -Rc /Applications/WeChat.app ~/Applications/WeChat Multi/WeChat N.app`
   ——`-c` 参数启用 APFS 的 copy-on-write 克隆,几乎不占额外磁盘空间,
   直到微信本身写入文件
2. 改写 `Contents/Info.plist`:
   - `CFBundleIdentifier` → `com.wechatmulti.cloneN`
   - `CFBundleName` / `CFBundleDisplayName` → 你给它起的名字
     (默认 `WeChat N`)
3. 删除 `Contents/_CodeSignature`(改了 Info.plist 之后原签名就失效了)
4. `codesign --force --deep --sign - <克隆路径>`(ad-hoc 重新签名)
5. `xattr -dr com.apple.quarantine <克隆路径>`(去掉 Gatekeeper 隔离标记)
6. `open -na <克隆路径>`

每个克隆拥有不同的 Bundle ID,因此 macOS 会为它分配独立的沙盒容器,
微信自身的"已经在运行"检查也就找不到匹配项了。

**ad-hoc 签名的代价**:依赖腾讯 Team ID 的钥匙串访问权限会失效,
所以多个克隆之间不共享密码 —— 每个实例都要单独扫码登录。对于多
账号场景这其实正是我们想要的。

## 卸载

```bash
# 在菜单里退出 WeChat Multi 后:
rm -rf "/Applications/WeChat Multi.app"
rm -rf "$HOME/Applications/WeChat Multi"
rm -rf "$HOME/Library/Containers/com.wechatmulti.clone"*
defaults delete com.wechatmulti.app 2>/dev/null
```

## 注意事项

- 微信只会更新 `/Applications/WeChat.app`,克隆是只读副本 —— 微信
  升级后请用菜单里的 **刷新过期克隆** 重建。这一步会自动检测并提示
- macOS 把每个克隆当作独立应用 —— 第一次需要摄像头、麦克风、屏幕
  录制权限时会有标准授权弹窗,需要手动确认一次
- 通知也是按 Bundle ID 区分的,所以每个实例都有独立的通知样式
  和"专注模式"白名单设置
- 本工具非官方,与腾讯无关。请自行评估风险。如果未来微信改变
  单实例检测机制,克隆方案可能需要相应调整

## 项目结构

```
.
├── Package.swift                 # Swift Package Manager manifest
├── Sources/WeChatMulti/
│   ├── main.swift                # NSApplication 入口
│   ├── AppDelegate.swift         # 菜单栏 UI
│   └── WeChatLauncher.swift      # 克隆管理 + 进程检测
├── Resources/Info.plist          # 应用元数据(LSUIElement = true)
├── build.sh                      # swift build → .app 打包
└── install.sh                    # 拷贝到 /Applications 并启动
```

## 贡献

欢迎 PR。一些可能的方向:

- 通用二进制构建(目前仅支持 arm64)
- 通过 `SMAppService` 实现"登录时启动"
- 完整的 `.icns` 图标和"关于"面板插画
- 支持 Homebrew Cask 安装
- 通知:首次克隆完成时弹出提示

## 许可证

[MIT](LICENSE) © 2026 ashinno

微信(WeChat)是腾讯控股有限公司的商标。本项目与腾讯无任何关联,
也未获得腾讯赞助或认可。
