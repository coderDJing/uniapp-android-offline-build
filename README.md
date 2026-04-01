# uniapp-android-offline-build

把 `uni-app` 离线 Android 打包里那套又臭又长的手工流程，收敛成一条 PowerShell 命令。

这个仓库专门解决下面这条链路：

1. 调 HBuilderX CLI 导出 `appResource`
2. 把资源覆盖到 Android 离线壳工程的 `assets/apps/<appid>`
3. 执行 Gradle 任务生成 `apk` 或 `aab`
4. 可选把最新 `apk` 复制到桌面或自定义目录

如果你现在正卡在 `uni-app + HBuilderX + Android Studio 离线壳工程` 这条线上，这玩意能省你不少重复劳动。

## 这仓库适合谁

- 正在使用 `uni-app`
- 本地通过 HBuilderX 导出 `appResource`
- 已经有可用的 Android 离线壳工程
- 想把“导资源 + 拷资源 + Gradle 打包”串成一键执行

如果你走的是云打包、CI/CD 云构建，或者根本不用离线壳工程，这仓库对你帮助不大。

## 功能

- 支持自动启动 HBuilderX
- 支持调用 HBuilderX CLI 导出 `appResource`
- 支持按 `appid` 定位资源目录，也支持手动覆盖资源目录
- 支持自动覆盖壳工程里的 `assets/apps/<appid>`
- 支持执行 `assembleRelease`、`bundleRelease` 等 Gradle 任务
- 支持自动搜索构建产物并复制最新 `apk`

## 环境要求

- Windows PowerShell 5.1+
- HBuilderX，且能访问 `cli.exe`
- 可正常打开的 `uni-app` 项目
- 已配置好的 Android Studio 离线壳工程
- 可用的 Java 运行时

## 目录结构

```text
.
├─ config.example.ps1
├─ scripts/
│  └─ build-uniapp-android-offline.ps1
└─ README.md
```

## 配好后的“一键执行”命令

在仓库根目录把 `config.local.ps1` 配好之后，直接执行这句：

```powershell
powershell -ExecutionPolicy Bypass -File "./config.local.ps1"
```

如果你当前就在 PowerShell 里，并且允许执行本地脚本，也可以直接：

```powershell
./config.local.ps1
```

## 推荐用法

别每次手敲一长串参数，纯属给自己找罪受。直接抄一份配置文件改成你自己的路径。

### 1. 复制示例配置

```powershell
Copy-Item "./config.example.ps1" "./config.local.ps1"
```

### 2. 修改你自己的本地配置

把下面这些路径按你自己的机器改掉：

- `HBuilderXCliPath`
- `HBuilderXExecutablePath`
- `UniAppProjectPath`
- `AndroidStudioProjectPath`
- `AndroidAppModuleName`
- `JavaHome`

`config.local.ps1` 已经被 `.gitignore` 忽略，不会误提交。

### 3. 直接执行

```powershell
powershell -ExecutionPolicy Bypass -File "./config.local.ps1"
```

这句命令需要在仓库根目录执行，也就是和 `config.local.ps1` 同级的位置。

## 配置文件示例

仓库内置了一个可直接改的 [config.example.ps1](./config.example.ps1)。

它本质上就是把参数收进一个 hashtable，再用 splatting 调用主脚本。这样配置和脚本逻辑分开，后面换项目也不至于改得乱七八糟。

## 也可以直接传参

如果你就想单次执行，也可以直接调主脚本：

```powershell
powershell -ExecutionPolicy Bypass -File "./scripts/build-uniapp-android-offline.ps1" `
  -HBuilderXCliPath "C:/tools/HBuilderX/cli.exe" `
  -HBuilderXExecutablePath "C:/tools/HBuilderX/HBuilderX.exe" `
  -UniAppProjectPath "D:/projects/demo-uniapp" `
  -AndroidStudioProjectPath "D:/projects/HBuilder-Integrate-AS" `
  -AndroidAppModuleName "simpleDemo" `
  -JavaHome "C:/Program Files/Android/Android Studio/jbr"
```

## 参数说明

| 参数 | 说明 |
| --- | --- |
| `HBuilderXCliPath` | HBuilderX 的 `cli.exe` 路径 |
| `HBuilderXExecutablePath` | HBuilderX 主程序路径；用于自动启动 HBuilderX |
| `AutoStartHBuilderX` | HBuilderX 未启动时是否自动拉起 |
| `UniAppProjectPath` | `uni-app` 项目根目录 |
| `UniAppProjectName` | HBuilderX CLI 使用的项目名；默认取项目目录名 |
| `PublishPlatform` | 默认 `app-android`，老版本也可传 `APP` |
| `UniAppAppId` | 可留空，脚本会从 `manifest.json` 尝试读取 |
| `ResourceRootOverride` | 手动指定导出的资源目录 |
| `AndroidStudioProjectPath` | Android 离线壳工程根目录 |
| `AndroidAppModuleName` | 承载资源和 Gradle 任务的模块名 |
| `AssetsAppsRoot` | 默认是 `<AndroidStudioProjectPath>/<AndroidAppModuleName>/src/main/assets/apps` |
| `GradleExecutable` | 默认是 `<AndroidStudioProjectPath>/gradlew.bat` |
| `GradleTask` | 默认 `assembleRelease`；如果设为 `bundleRelease` 会搜索 `aab` |
| `GradleExtraArgs` | 额外的 Gradle 参数，默认 `--no-daemon` |
| `JavaHome` | Java 目录；不传就尝试沿用环境变量 `JAVA_HOME` |
| `CopyLatestApkToOutputDir` | 是否复制最新 `apk` 到输出目录 |
| `OutputDir` | 输出目录；默认桌面 |
| `OpenProjectBeforePublish` | 导出前是否先调用 HBuilderX 打开项目 |
| `RunPublish` | 是否执行 HBuilderX 资源导出 |
| `RunCopy` | 是否复制资源到壳工程 |
| `RunGradle` | 是否执行 Gradle 打包 |
| `CleanTargetAppDir` | 覆盖前是否先删除壳工程中的旧目录 |

## 默认行为

- 默认会尝试自动启动 HBuilderX
- 默认会执行资源导出
- 默认会覆盖壳工程中的目标 `appid` 目录
- 默认会执行 Gradle 打包
- 默认会把最新 `apk` 复制到输出目录

如果你只想单独跑某一步，直接把对应布尔参数改成 `$false`。

## 常见问题

### 1. 脚本读不到 `appid`

脚本默认从 `manifest.json` 里按正则读取 `appid`。如果你的配置结构比较特别，直接传 `-UniAppAppId`。

### 2. 找不到资源目录

脚本默认找下面这个目录：

```text
<UniAppProjectPath>/unpackage/resources/<appid>
```

如果找不到，会退回到 `unpackage/resources` 下最近更新的目录。你也可以直接传 `-ResourceRootOverride`。

### 3. 我想产出 `aab`

把 `GradleTask` 改成 `bundleRelease`。

### 4. 我只想把资源拷进壳工程，不想立刻打包

把 `RunGradle` 改成 `$false`。

## 已知边界

- 这是 Windows PowerShell 脚本，不是跨平台方案
- 这不是完整 CI 工具，只是把本地离线打包流程自动化
- `appid` 读取目前基于正则，不是完整 JSON 解析器

## License

MIT
