# RetroEngine

基于 Flutter 的 **SaveDeck 游戏库管理 + ScreenScraper 自动搜刮工具**，仅面向 Android。

[GitHub 仓库](https://github.com/BanBrick-zhang/RetroEngine) · [问题反馈](https://github.com/BanBrick-zhang/RetroEngine/issues) · 当前版本：`0.0.1`

RetroEngine（pubspec 包名 `savedeck_toolkit`）直接读写设备共享存储中的游戏库目录，识别各平台 ROM 与 `savedeck.toml`，并从 ScreenScraper.fr 拉取封面（box-2D）、视频与简介，写回配置与 `media/` 目录。

## 一、功能

- **游戏库**：绑定游戏库总目录后自动扫描各平台子目录，识别 ROM；无 `savedeck.toml`
  时按扩展名自动生成条目，搜刮或保存时自动创建配置文件。
- **单条搜刮**：优先用 CRC32/MD5/SHA1 精确匹配，失败回落名称搜索；支持候选选择、
  手动按名称搜索、封面/视频/简介写入。
- **批量搜刮**：勾选多个游戏，可选是否下载封面与视频，逐条展示处理状态。
- **编辑游戏**：名称、ROM 路径、排序、封面、视频、启动指令、UUID、简介均可编辑。
- **设置**：游戏库目录、ScreenScraper 账号与开发者凭据、首选语言、下载开关。
- **权限引导**：绑定目录后检测真实读写权限，可直达系统「所有文件访问权限」页面；
  授权返回应用后自动重新读取，无需重新选择目录。

## 二、快速开始

```bash
git clone https://github.com/BanBrick-zhang/RetroEngine.git
cd RetroEngine
git checkout 0.0.1
flutter pub get
flutter build apk
```

产物：`build/app/outputs/flutter-apk/app-release.apk`。

### 1. 环境要求

- Flutter 3.0.0（Dart 2.17）
- JDK 11（项目使用 Gradle 6.7 + AGP 4.1.0，更高版本 JDK 会构建失败）
- Android SDK Platform 31 / Build-Tools 31.0.0

### 2. 一次性环境准备（新环境参考）

```bash
# JDK 11
sdk install java 11.0.23-zulu

# Android cmdline-tools（需 v7.0 旧版本，新版要求 JDK 17+）
mkdir -p /opt/android-sdk/cmdline-tools
curl -sSL -o ct.zip https://dl.google.com/android/repository/commandlinetools-linux-8512546_latest.zip
unzip -q ct.zip -d /opt/android-sdk/cmdline-tools
mv /opt/android-sdk/cmdline-tools/cmdline-tools /opt/android-sdk/cmdline-tools/latest

export ANDROID_HOME=/opt/android-sdk
yes | $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --sdk_root=$ANDROID_HOME --licenses
$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --sdk_root=$ANDROID_HOME \
  "platform-tools" "platforms;android-31" "build-tools;31.0.0"

flutter config --android-sdk /opt/android-sdk
flutter doctor
```

> 说明：
> - 当前 release 包使用 debug 签名（模板默认配置），正式发布前请在
>   `android/app/build.gradle` 中配置自己的签名。
> - 若构建报 `init.gradle` 语法错误，检查 `/root/.gradle/init.gradle` 的仓库配置。

### 3. 运行测试

```bash
flutter test
```

## 三、目录结构（仅 Android）

```
.
├── android/                          Android 平台工程（唯一构建目标）
│   └── app/src/main/kotlin/com/retroengine/app/MainActivity.kt  权限 MethodChannel
├── assets
│   └── screenscraper_systems.json    平台 systemeid 映射表
├── lib
│   ├── main.dart                     入口：游戏库 / 批量搜刮 / 设置 三个 Tab
│   ├── theme.dart                    灰白毛玻璃设计系统
│   ├── models/library.dart           数据模型与平台目录表
│   ├── data
│   │   ├── platform_extensions.dart  ES-DE 平台扩展名表
│   │   └── screenscraper_systems.dart  平台映射表加载器
│   ├── services
│   │   ├── toml_service.dart         savedeck.toml 解析与序列化
│   │   ├── library_service.dart      文件系统、权限、ROM 扫描、哈希、下载
│   │   ├── screenscraper_service.dart  ScreenScraper API v2 客户端
│   │   └── preferences_service.dart   设置持久化
│   ├── screens                       游戏库 / 详情 / 批量搜刮 / 设置 / 文件浏览器
│   └── widgets/permission_dialog.dart  权限引导
├── test                              单元测试（toml / library / screenscraper / systems）
├── tool/fetch_screenscraper_systems.dart  平台映射表生成脚本
├── pubspec.yaml
└── README.md
```

> `lib/` 根目录下的 `*_screen.dart`（`component_screen.dart` 等）为 Flutter 模板遗留文件，
> 当前入口未引用。

## 四、游戏库结构约定

```
<游戏库根目录>/
└── GBA/
    ├── savedeck.toml
    ├── 游戏A.gba
    └── media/
        └── 游戏A/
            ├── cover.png
            └── video.mp4
```

`savedeck.toml` 示例：

```toml
format_version = 1
platform = "GBA"
sort = "002"

[[games]]
name = "示例游戏"
file = "示例游戏.gba"
id = "7ca294ab-8018-45cd-9fc7-481d6b504bb3"
description = "游戏简介"
cover = "media/示例游戏/cover.png"
video = "media/示例游戏/video.mp4"
```

解析器兼容 UTF-8 / GBK 编码、多行字符串与内联表写法，未识别字段会原样保留。

## 五、ScreenScraper 搜刮

开发者凭据已内置在 `lib/services/screenscraper_service.dart` 的
`ScreenscraperConfig`（`devid` / `devpassword` / `softname`），无需在应用内填写。
设置页只需**可选**填写 ScreenScraper 账号（用户名，非邮箱）以提升配额，留空则匿名访问。

搜刮流程：

1. 平台 `systemeid` 来自 `assets/screenscraper_systems.json`，该文件由
   `systemesListe.php` 生成，可运行 `dart run tool/fetch_screenscraper_systems.dart` 刷新；
2. 用 `jeuRecherche.php` 按 `recherche` + `systemeid` 搜索，结果全部展示供用户手动选择；
3. 选定后通过 `jeuInfos.php` 获取 box-2D 封面、视频与简介（默认 en），
   下载到 `media/<游戏名>/` 并写回 `savedeck.toml`。

设置页「测试连接」调用 `ssuserInfos.php` 校验凭据，失败时显示脱敏的请求诊断信息。

## 六、Android 权限说明

- 需声明并使用 `MANAGE_EXTERNAL_STORAGE`（所有文件访问权限），该权限无法通过运行时
  弹窗授予，只能跳转系统设置页开启。
- 绑定目录后应用会引导跳转「特殊应用权限 → 所有文件访问权限」；开启后返回应用，
  目录已自动保存，会自动重新扫描，无需重新选择。

## 七、版本记录

### 0.0.1

- 首个公开发布版本。
- 游戏库扫描与 `savedeck.toml` 读写、单条与批量 ScreenScraper 搜刮、游戏编辑、
  设置持久化及 Android 所有文件访问授权引导。
