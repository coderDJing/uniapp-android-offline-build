# uniapp-android-offline-build

`uni-app + HBuilderX + Android shell project` 的离线 Android 打包脚本，目标是把下面这条流程串成一条 PowerShell 命令：

1. 用 HBuilderX CLI 导出 `appResource`
2. 把资源拷贝进离线 Android 壳工程的 `assets/apps/<appid>`
3. 执行 Gradle 任务产出 `apk` 或 `aab`
4. 可选把最新 `apk` 再复制到桌面或自定义输出目录

## 适用场景

- 你在用 `uni-app`
- 你走的是 `HBuilderX` 的本地打包资源导出流程
- 你已经有一个 Android Studio 离线壳工程
- 你想把“导出资源 + 覆盖壳工程 + Gradle 打包”变成一键执行

如果你走的不是这套链路，这个仓库对你没什么意义。

## 环境要求

- Windows PowerShell 5.1+
- HBuilderX，且可访问 `cli.exe`
- 可正常打开的 uni-app 项目
- 已配置好的 Android Studio 离线壳工程
- 可用的 Java 运行时（`JAVA_HOME` 或脚本参数传入）

## 目录说明

```text
.
├─ scripts/
│  └─ build-uniapp-android-offline.ps1
└─ README.md
```

## 快速开始

先按你自己的机器路径改参数，再运行：

```powershell
powershell -ExecutionPolicy Bypass -File "./scripts/build-uniapp-android-offline.ps1" `
  -HBuilderXCliPath "C:/tools/HBuilderX/cli.exe" `
  -HBuilderXExecutablePath "C:/tools/HBuilderX/HBuilderX.exe" `
  -UniAppProjectPath "D:/projects/demo-uniapp" `
  -AndroidStudioProjectPath "D:/projects/HBuilder-Integrate-AS" `
  -AndroidAppModuleName "simpleDemo" `
  -JavaHome "C:/Program Files/Android/Android Studio/jbr" `
  -OpenProjectBeforePublish:$true `
  -RunPublish:$true `
  -RunCopy:$true `
  -RunGradle:$true `
  -CopyLatestApkToOutputDir:$true
```

## 关键参数

| 参数 | 说明 |
| --- | --- |
| `HBuilderXCliPath` | HBuilderX 的 `cli.exe` 路径 |
| `HBuilderXExecutablePath` | HBuilderX 主程序路径；允许脚本自动拉起 HBuilderX |
| `UniAppProjectPath` | uni-app 项目根目录 |
| `UniAppProjectName` | HBuilderX CLI 使用的项目名；默认取项目目录名 |
| `PublishPlatform` | 默认 `app-android`，老版本也可以传 `APP` |
| `UniAppAppId` | 可留空，脚本会尝试从 `manifest.json` 读取 |
| `AndroidStudioProjectPath` | Android 壳工程根目录 |
| `AndroidAppModuleName` | 壳工程里承载资源和 Gradle 任务的模块名 |
| `AssetsAppsRoot` | 默认是 `<AndroidStudioProjectPath>/<AndroidAppModuleName>/src/main/assets/apps` |
| `GradleTask` | 默认 `assembleRelease`；如果用 `bundleRelease` 会找 `aab` |
| `JavaHome` | Java 目录；不传就尝试沿用环境变量 `JAVA_HOME` |
| `CopyLatestApkToOutputDir` | 是否复制最新 `apk` 到输出目录 |
| `OutputDir` | 输出目录；默认桌面 |

## 默认行为

- 默认会尝试自动启动 HBuilderX
- 默认会先执行 HBuilderX 资源导出
- 默认会覆盖壳工程里目标 `appid` 对应目录
- 默认会执行 Gradle 打包
- 默认会把最新 `apk` 复制到输出目录

如果你只想跑其中某一步，可以把对应布尔参数设为 `$false`。

## 常见问题

### 1. 读不到 `appid`

脚本会优先从 `manifest.json` 里按正则读取 `appid`。如果你的文件结构特殊，直接手动传 `-UniAppAppId`。

### 2. 找不到资源目录

默认会找：

```text
<UniAppProjectPath>/unpackage/resources/<appid>
```

如果这个目录不存在，脚本会退回到 `unpackage/resources` 下最近更新的目录。你也可以直接传 `-ResourceRootOverride` 指向资源目录。

### 3. 要产出 `aab`

把 `-GradleTask` 改成 `bundleRelease` 即可。

## 说明

这个脚本解决的是“把偏手工的离线打包流程串起来”这一个问题，不试图抽象成完整的构建平台。欢迎按自己的项目继续改。
