# Copy this file to config.local.ps1 and replace the placeholder paths with your own environment.

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildScriptPath = Join-Path -Path $repoRoot -ChildPath "scripts/build-uniapp-android-offline.ps1"

$buildConfig = @{
	HBuilderXCliPath            = "C:/tools/HBuilderX/cli.exe"
	HBuilderXExecutablePath     = "C:/tools/HBuilderX/HBuilderX.exe"
	AutoStartHBuilderX          = $true
	HBuilderXStartupWaitSeconds = 8

	UniAppProjectPath           = "D:/projects/demo-uniapp"
	UniAppProjectName           = ""
	PublishPlatform             = "app-android"
	UniAppAppId                 = ""
	ResourceRootOverride        = ""

	AndroidStudioProjectPath    = "D:/projects/HBuilder-Integrate-AS"
	AndroidAppModuleName        = "simpleDemo"
	AssetsAppsRoot              = ""

	GradleExecutable            = ""
	GradleTask                  = "assembleRelease"
	GradleExtraArgs             = @("--no-daemon")
	JavaHome                    = "C:/Program Files/Android/Android Studio/jbr"

	CopyLatestApkToOutputDir    = $true
	OutputDir                   = ""
	OutputApkNameFormat         = "yyyyMMddHHmmss"

	OpenProjectBeforePublish    = $true
	RunPublish                  = $true
	RunCopy                     = $true
	RunGradle                   = $true
	CleanTargetAppDir           = $true
}

& $buildScriptPath @buildConfig
