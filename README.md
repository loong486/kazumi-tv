<div align="center">

<h1>Kazumi TV</h1>

<img src="assets/images/logo/logo_rounded.png" width="160" alt="Kazumi TV Logo" />

<p>
  <img src="https://img.shields.io/badge/Platform-Android%20TV-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android TV" />
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/License-GPL--3.0-blue?style=for-the-badge" alt="GPL-3.0" />
  <a href="https://github.com/loong486/kazumi-tv/releases/latest">
    <img src="https://img.shields.io/github/v/release/loong486/kazumi-tv?style=for-the-badge&label=Release" alt="Latest Release" />
  </a>
</p>

<p>
  基于 <a href="https://github.com/Predidit/Kazumi">Predidit/Kazumi</a>（v2.4.6 基线）打造的<strong>纯 Android TV 专用番剧客户端</strong>。<br/>
  专为客厅大屏与电视遥控器重新设计交互、焦点系统与播放器，支持自定义 XPath 规则、多源弹幕、跨设备同步与应用内在线更新。
</p>

</div>

---

## 核心特性

- **10ft 客厅大屏与遥控器交互**
  - 专为 Android TV 设计的左侧导航栏（热门 / 时间表 / 搜索 / 追番 / 历史 / 规则 / 设置），去除手机端触屏组件与手势依赖。
  - 自定义 `TvFocusTraversalPolicy` 与 `TvAxisClipRect` 焦点高亮体系：方向键上下左右不跳行、列表边缘辉光不裁切、返回键分级回退防误触退出。
  - 独立包名 `com.predidit.kazumi.tv`，自带 Android TV Leanback 桌面横幅（Banner），可与原版手机/平板 Kazumi 共存。
- **遥控器优先的视频与弹幕播放器**
  - 基于 `media_kit` 硬件解码与低内存友好策略，适配大屏高帧率显示模式。
  - 内置多源弹幕渲染（B 站 / 巴哈姆特 / 弹弹 play），支持在播放页遥控器手动搜索和切换弹幕源。
  - 播放界面方向键上/下统一唤起控制栏与功能抽屉（选集、线路/换源、倍速、画面比例、弹幕设置），左/右键快退快进。
- **规则仓库与数据同步**
  - 完整兼容 [Predidit/KazumiRules](https://github.com/Predidit/KazumiRules) XPath 规则，首次启动向导支持网络连通检测与规则一键导入，支持启动时自动检查规则更新。
  - 支持 WebDAV 同步观看历史、追番收藏与弹幕屏蔽词，支持 Bangumi 收藏同步。
- **应用内在线更新（OTA）**
  - 基于 GitHub Releases 与自动生成的 `latest.json` 清单，按设备 `SUPPORTED_ABIS` 自动匹配对应架构 APK。
  - 内置多镜像降级链（`gh-proxy` / `ghfast` / 自定义镜像 / 直连 GitHub），下载过程使用流式 SHA-256 校验，校验通过后直接调起系统安装器覆盖升级。

## 支持环境

- **系统要求**：Android TV / 智能电视 / 电视盒子，**Android 7.0（API 24）及以上**（推荐 Android 9+）。
- **架构支持**：提供 `arm64-v8a`、`armeabi-v7a`、`x86_64` 分架构安装包。
- **已验证机型特性**：兼容标准 Android TV Leanback 遥控器及 TCL 等国产电视遥控器键值与焦点行为。

## 下载与安装

前往本仓库 [Releases 页面](https://github.com/loong486/kazumi-tv/releases/latest) 下载对应架构的 APK：

<a href="https://github.com/loong486/kazumi-tv/releases/latest">
  <img src="static/svg/get_it_on_github.svg" alt="Get it on GitHub" width="200" />
</a>

| 安装包文件名 | 适用设备 |
| :--- | :--- |
| `KazumiTV_<版本>_arm64-v8a.apk` | **绝大多数现代 64 位 Android TV / 电视盒子（首选）** |
| `KazumiTV_<版本>_armeabi-v7a.apk` | 较老的 32 位 ARM 电视 / 盒子 |
| `KazumiTV_<版本>_x86_64.apk` | x86_64 架构设备或 Android TV 模拟器 |

### 安装方式
- **U 盘 / 电视文件管理器安装**：下载对应 APK 拷贝至 U 盘或通过电视局域网传文件安装（国产电视需在系统设置中允许安装未知来源应用）。
- **无线 ADB 安装**：
  ```bash
  adb connect <电视IP>:5555
  adb install -r KazumiTV_<版本>_arm64-v8a.apk
  ```

## 遥控器按键说明

| 场景 | 按键 | 功能 |
| :--- | :--- | :--- |
| **主界面 / 列表** | 方向键 `↑ ↓ ← →` | 移动焦点；列表最左侧按 `←` 返回左侧导航栏 |
| **主界面 / 列表** | `OK / 确认` | 打开番剧详情 / 切换筛选或开关 |
| **主界面 / 列表** | `返回` | 逐级退回上一页 -> 回到左侧栏 -> 回到「热门」 -> 首页双击退出 |
| **播放界面** | `OK / 确认` | 暂停 / 恢复播放 |
| **播放界面** | `← / →` | 快退 / 快进（可在设置中自定义步长） |
| **播放界面** | `↑ / ↓` | 唤起播放控制栏与选集 / 换源 / 弹幕 / 播放设置抽屉 |
| **播放界面** | `返回` | 关闭抽屉或控制栏；无浮层时双击退出播放 |

## 应用内在线更新配置

进入 **设置 -> 关于与日志**：
- **检查应用更新**：手动拉取最新 Release 信息并按当前电视 CPU 架构下载安装。
- **启动时自动检查更新**：默认开启，进入首页后静默检查，支持「忽略此版本」。
- **更新下载镜像**：支持切换 `gh-proxy`、`ghfast`、**自定义镜像**（如自建 Cloudflare Worker 加速前缀）或直连 GitHub；下载失败时会自动按降级链重试。
- **更新仓库**：默认指向 `loong486/kazumi-tv`，可自定义为其他 fork 仓库地址。

## 自行构建与自动发版

### 本地构建
```bash
flutter pub get
flutter build apk --release --split-per-abi --dart-define=TV_UPDATE_REPO=loong486/kazumi-tv
```

### 正式签名配置
复制 [android/key.properties.example](android/key.properties.example) 为 `android/key.properties`（已被 `.gitignore` 忽略）并按注释生成 `.jks` 签名密钥；未配置密钥时，本地 `release` 构建会自动回退为 debug 签名。

### GitHub Actions 自动发布
推送 `v*` 格式标签（如 `v1.0.1`）或在 Actions 页面手动触发 [Release Android TV](.github/workflows/release.yaml) 工作流，将自动执行：
1. `flutter analyze --no-fatal-infos --fatal-warnings` 与全量 `flutter test`；
2. 解密仓库 Secrets（`TV_KEYSTORE_BASE64`、`TV_KEYSTORE_PASSWORD`、`TV_KEY_ALIAS`、`TV_KEY_PASSWORD`）并构建三架构正式签名 APK；
3. 运行 [tool/generate_update_manifest.dart](tool/generate_update_manifest.dart) 生成 `latest.json` 与 `SHA256SUMS.txt` 并发布至 GitHub Release。

## 美术资源与字体声明

- 应用图标源自原作者 [Yuquanaaa](https://www.pixiv.net/users/66219277) 在 [Pixiv](https://www.pixiv.net/artworks/116666979) 的作品，继承自上游 Kazumi 项目授权，未经原作者明确授权不得用于其他商业或独立分发用途。
- 内嵌字体为小米开发的 [Mi Sans](https://hyperos.mi.com/font/zh/details/sc/) 字体，版权归 Xiaomi 所有。

## 免责声明与隐私政策

- 本项目遵循 **GNU General Public License v3.0（GPL-3.0）** 开源协议，详见 [LICENSE](LICENSE)。
- 本软件本身不提供、不存储任何视频资源，所有播放源均由用户自行导入的规则动态解析；请遵守当地法律法规，勿将本软件用于任何商业或侵权用途。
- **隐私政策**：本应用不收集任何用户个人数据，不包含任何广告或遥测统计组件。

## 致谢

- 感谢上游项目 **[Predidit/Kazumi](https://github.com/Predidit/Kazumi)** 及其所有贡献者提供了坚实的番剧采集、播放与同步架构。
- 感谢 **[Predidit/KazumiRules](https://github.com/Predidit/KazumiRules)** 社区维护的丰富番剧规则。
- 感谢 **[Bangumi](https://bangumi.tv/)**、**[弹弹play](https://www.dandanplay.com/)**、**[media-kit](https://github.com/media-kit/media-kit)**、**[XpathSelector](https://github.com/simonkimi/xpath_selector)** 与 **[hive_ce](https://pub.dev/packages/hive_ce)** 等开源项目与开放平台。
