# RetroEngine

基于 Flutter 的 **SaveDeck 游戏库管理 + ScreenScraper 自动搜刮工具**，仅面向 Android。

[GitHub 仓库](https://github.com/BanBrick-zhang/RetroEngine) · [问题反馈](https://github.com/BanBrick-zhang/RetroEngine/issues) · 当前版本：`0.1.2`

RetroEngine（pubspec 包名 `savedeck_toolkit`）直接读写设备共享存储中的游戏库目录，识别各平台 ROM 与 `savedeck.toml`，并从 ScreenScraper.fr 拉取封面（box-2D）、视频、简介、开发商、发售日期及 wheel、box-texture、box-3D、support-2D、fanart、mixrbv 等资源，写回配置与 `media/` 目录。

## 一、功能

- **游戏库**：绑定游戏库总目录后自动扫描各平台子目录，识别 ROM；无 `savedeck.toml`
  时按扩展名自动生成条目，搜刮或保存时自动创建配置文件。「游戏库」标题与平台标签
  合并为顶部同一行，平台可横向滚动切换；右上角可切换列表视图、网格视图与轮播图
  视图，选择会被记住。横屏优先：网格按可用宽度自适应列数、列表变为双列紧凑行、
  轮播图左侧大封面右侧信息栏，一屏展示更多内容。竖屏轮播卡片上下排列封面与简介，
  保证首屏完整可见；卡片统一带阴影、按压缩放反馈与翻页缩放淡入动画。
- **次级菜单**：左上角菜单按钮滑出侧栏（横屏约占 1/4 屏宽），依次为账号、
  游戏生涯、云存档、设置选项；账号页展示 ScreenScraper 账号状态并可跳转设置，
  游戏生涯与云存档为后续功能预留说明页。
- **游戏详情**：只读展示，支持列表视图与轮播视图两种模式（可记住）。
  轮播视图左侧显示 box2D 封面、开发商、发行日期与简介，右侧依次轮播
  wheel / box-texture / support-2D / fanart / mixrbv / 视频。横屏时列表视图
  自动分左右两栏（信息+简介 / 视频+缩略图），信息栏宽度与封面高度随屏幕伸缩。
- **编辑游戏**：详情页右上角「编辑」弹窗内统一完成——名称、ROM 路径、排序、开发商、
  发售日期、封面、视频、各类附加资源路径、启动指令、UUID、简介均可编辑；
  横屏/宽屏下基本信息与媒体资源分两列并排显示，减少纵向滚动；「手动搜刮」按钮
  置于弹窗顶部，可随时点击。可单独删除封面图片、视频、附加图片资源或简介；
  保存时可开启按游戏名同步重命名 ROM（保留扩展名）与 media 媒体目录。
- **手动搜刮**：按名称搜索并选择候选，可勾选全部 11 类内容（默认开发商、发行日期、
  box2D、简介、视频）；任务提交后在后台下载，编辑弹窗与详情页均可查看进度条，
  不阻塞其他操作。
- **设置**：游戏库目录、ScreenScraper 账号（开发者凭据仅构建期注入，应用内不可填写）、
  首选语言、搜刮选项、游戏详情页展示内容、视频延时自动播放、ROM 与媒体目录重命名开关；
  所有菜单默认折叠，入口在左上角次级菜单的「设置选项」。
- **添加 ROM**：源文件若已在目标平台目录内则直接引用，不再重复复制；添加后自动打开
  编辑弹窗便于立即搜刮。
- **操作适配**：以横屏为主要使用场景，竖屏为次要场景，各页面横屏均做了
  分栏/多列适配；无底部导航栏，默认进入游戏库，支持手柄/键盘方向键焦点导航。
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
│   ├── main.dart                     入口：游戏库单页 + 顶部设置入口，全局后台进度面板
│   ├── theme.dart                    灰白毛玻璃设计系统
│   ├── models/library.dart           数据模型与平台目录表
│   ├── data
│   │   ├── platform_extensions.dart  ES-DE 平台扩展名表
│   │   └── screenscraper_systems.dart  平台映射表加载器
│   ├── services
│   │   ├── toml_service.dart         savedeck.toml 解析与序列化
│   │   ├── library_service.dart      文件系统、权限、ROM 扫描、哈希、下载
│   │   ├── screenscraper_service.dart  ScreenScraper API v2 客户端
│   │   ├── preferences_service.dart   设置持久化
│   │   ├── background_scrape_service.dart  后台搜刮队列与进度
│   │   └── version_service.dart       读取 pubspec 版本号
│   ├── screens                       游戏库 / 详情 / 设置 / 文件浏览器
│   └── widgets
│       ├── game_edit_dialog.dart     游戏编辑弹窗（含资源路径与搜刮）
│       ├── library_carousel.dart     游戏库轮播图视图
│       ├── video_preview.dart        内嵌视频播放
│       └── permission_dialog.dart    权限引导
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
            ├── cover-7ca294ab-8018-45cd-9fc7-481d6b504bb3.png
            └── video-7ca294ab-8018-45cd-9fc7-481d6b504bb3.mp4
```

> 搜刮下载的媒体文件统一以 `<资源类型>-<游戏 UUID>.<扩展名>` 命名，
> 同时兼容旧版本无 UUID 的 `cover.png` / `video.mp4` 等文件。

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
cover = "media/示例游戏/cover-7ca294ab-8018-45cd-9fc7-481d6b504bb3.png"
video = "media/示例游戏/video-7ca294ab-8018-45cd-9fc7-481d6b504bb3.mp4"
developpeur = "Square"
dates = "1994-04-02"
wheel = "media/示例游戏/wheel-7ca294ab-8018-45cd-9fc7-481d6b504bb3.png"
box-texture = "media/示例游戏/box-texture-7ca294ab-8018-45cd-9fc7-481d6b504bb3.png"
box-3D = "media/示例游戏/box-3D-7ca294ab-8018-45cd-9fc7-481d6b504bb3.png"
support-2D = "media/示例游戏/support-2D-7ca294ab-8018-45cd-9fc7-481d6b504bb3.png"
fanart = "media/示例游戏/fanart-7ca294ab-8018-45cd-9fc7-481d6b504bb3.jpg"
mixrbv = "media/示例游戏/mixrbv-7ca294ab-8018-45cd-9fc7-481d6b504bb3.png"
```

解析器兼容 UTF-8 / GBK 编码、多行字符串与内联表写法，未识别字段会原样保留。

## 五、ScreenScraper 搜刮

源码与仓库中**不包含**任何 ScreenScraper 开发者凭据。开发者凭据只能在构建期注入：

1. 构建注入（推荐分发时使用）：`android/app/build.gradle` 会读取环境变量
   `SS_DEV_ID` / `SS_DEV_PASSWORD`（或 `android/local.properties` 中的同名键），
   自动以 dart-define 形式传给 Dart 编译器，无需额外命令行参数：

   ```bash
   SS_DEV_ID=<你的 devid> SS_DEV_PASSWORD=<你的 devpassword> flutter build apk
   ```

   也可以直接使用命令行参数（优先级最高）：

   ```bash
   flutter build apk \
     --dart-define=SS_DEV_ID=<你的 devid> \
     --dart-define=SS_DEV_PASSWORD=<你的 devpassword>
   ```

   写入 `android/local.properties`（该文件不入库）后，直接 `flutter build apk`
   即可完成注入：

   ```properties
   SS_DEV_ID=<你的 devid>
   SS_DEV_PASSWORD=<你的 devpassword>
   ```

个人 ScreenScraper 账号（用户名，非邮箱）为**可选**，在「设置 → ScreenScraper 账号」中
填写后可提升配额，留空则匿名访问。应用内**不再提供**开发者凭据填写入口。

搜刮流程：

1. 平台 `systemeid` 来自 `assets/screenscraper_systems.json`，该文件由
   `systemesListe.php` 生成，可运行
   `SS_DEV_ID=<devid> SS_DEV_PASSWORD=<devpassword> dart run tool/fetch_screenscraper_systems.dart` 刷新；
2. 用 `jeuRecherche.php` 按 `recherche` + `systemeid` 搜索，结果全部展示供用户手动选择；
3. 选定后通过 `jeuInfos.php` 获取完整详情：box-2D 封面、`video-normalized` 视频、
   简介（默认 en）、开发商（`developpeur`）与发售日期（`dates`，优先 jp、us），以及
   `wheel`、`box-texture`、`box-3D`、`support-2D`、`fanart`、`mixrbv` 资源；
4. 资源以标签名保存为 `media/<游戏名>/wheel.png`、`box-texture.png`、`fanart.jpg` 等，
   并在 `savedeck.toml` 的 `[[games]]` 中以 `wheel`、`box-texture`、`fanart` 等键引用。

设置页「测试连接」调用 `ssuserInfos.php` 校验凭据，失败时显示脱敏的请求诊断信息。

## 六、翻译（可选）

手动搜索、游戏名与简介支持翻译，使用接口盒子（apihz.cn）聚合翻译接口：

- 开发者 ID `10021309` 已内置，只需在「设置 → 翻译」填写通讯 KEY；
- 含中文时译为英文（便于搜索），否则译为中文（便于名称/简介阅读）；
- 翻译结果会写回输入框，可手动修改后再搜索或保存到 `savedeck.toml`；
- 长简介会自动按句分段（单段不超过 1200 字符），段间留出间隔以适配免费账号
  约 10 次/分钟的频次限制。

## 七、Android 权限说明

- 需声明并使用 `MANAGE_EXTERNAL_STORAGE`（所有文件访问权限），该权限无法通过运行时
  弹窗授予，只能跳转系统设置页开启。
- 绑定目录后应用会引导跳转「特殊应用权限 → 所有文件访问权限」；开启后返回应用，
  目录已自动保存，会自动重新扫描，无需重新选择。

## 八、版本记录

### 0.1.2

- 新增模拟器管理：内置模拟器目录与模拟器选择器，支持为平台/游戏配置启动指令并直接拉起游戏。
- 新增云存档：基于 WebDAV 的存档上传、下载与同步，新增云存档页面与相关服务。
- 游戏库支持拼音首字母检索、轮播展示与侧边菜单，游戏编辑改为独立弹窗/页面，新增视频预览与统一 Toast、信息弹窗组件。
- 重构游戏详情与游戏库页面，扩展搜刮选项与资源字段模型；设置项与偏好持久化同步扩充。
- 仓库不再跟踪 APK 产物，`*.apk` 已加入 `.gitignore`；开发者凭据仍仅在构建期注入。

### 0.0.7

- 搜刮新增开发商、发售日期（优先 jp/us）及 wheel、box-texture、box-3D、support-2D、
  fanart、mixrbv 资源，统一以标签名存入 `media/<游戏名>/` 并写入 `savedeck.toml`。
- 视频默认选用 `video-normalized`；搜索结果缺详情时自动补拉 `jeuInfos.php`。
- 手动搜索使用英文译名时，搜刮前弹窗确认是否将译名应用为游戏名，默认不应用。
- 修改排序值后同步调整 `[[games]]` 在 TOML 中的先后位置；搜刮完成提示 1 秒后自动隐藏。
- 移除设置页的开发者凭据选项，`devid` / `devpassword` 仅随构建注入。

### 0.0.6

- 移除源码中硬编码的 ScreenScraper 开发者凭据，改为构建期注入（环境变量
  `SS_DEV_ID` / `SS_DEV_PASSWORD`、`android/local.properties` 或 `--dart-define`）
  或在设置页填写；映射表工具改用环境变量提供凭据。
- 搜刮任务改为后台队列，编辑页内嵌进度条；新增中英翻译，长文本自动分段。
- 更新自适应启动图标与仓库文档。

### 0.0.5

- 新增统一页面切换动画（淡入 + 轻微上移）与淡入缩放的加载指示器，页面切换更连贯。
- 游戏库支持手柄快捷键：A 打开当前平台首个游戏、X 添加 ROM、L/R 切换平台、
  START 打开设置，底部常驻按键提示。
- 设置页适配安全区并统一背景，保存时默认开启 media 媒体目录重命名。
- 更新自适应应用图标。

### 0.0.3

- 重做灰白动态毛玻璃界面；游戏详情页新增视频小窗与分项搜刮选择。
- 手动搜刮改为后台队列，编辑界面内嵌进度条；移除一键搜刮与批量搜刮入口。
- 应用图标改为自适应图标；设置菜单默认折叠，新增视频延时自动播放与保存时重命名 ROM 开关。
- 适配横屏四列网格与手柄/键盘方向键导航；移除底部导航栏，设置入口移至顶部右侧。
- 支持按类型删除 media 资源、保存时同步重命名媒体目录；添加 ROM 时跳过已在平台目录的文件。

### 0.0.2

- 修复 ScreenScraper 侧边/背面图被误当作正面封面的问题，新增翻译功能与平台映射表更新工具。

### 0.0.1

- 首个公开发布版本。
- 游戏库扫描与 `savedeck.toml` 读写、单条与批量 ScreenScraper 搜刮、游戏编辑、
  设置持久化及 Android 所有文件访问授权引导。
