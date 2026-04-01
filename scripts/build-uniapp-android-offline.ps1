#requires -Version 5.1

[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[string]$HBuilderXCliPath,

	[string]$HBuilderXExecutablePath = "",

	[bool]$AutoStartHBuilderX = $true,

	[int]$HBuilderXStartupWaitSeconds = 8,

	[Parameter(Mandatory = $true)]
	[string]$UniAppProjectPath,

	[string]$UniAppProjectName = "",

	[string]$PublishPlatform = "app-android",

	[string]$UniAppAppId = "",

	[string]$ResourceRootOverride = "",

	[Parameter(Mandatory = $true)]
	[string]$AndroidStudioProjectPath,

	[Parameter(Mandatory = $true)]
	[string]$AndroidAppModuleName,

	[string]$AssetsAppsRoot = "",

	[string]$GradleExecutable = "",

	[string]$GradleTask = "assembleRelease",

	[string[]]$GradleExtraArgs = @("--no-daemon"),

	[string]$JavaHome = "",

	[bool]$CopyLatestApkToOutputDir = $true,

	[string]$OutputDir = "",

	[string]$OutputApkNameFormat = "yyyyMMddHHmmss",

	[bool]$OpenProjectBeforePublish = $true,

	[bool]$RunPublish = $true,

	[bool]$RunCopy = $true,

	[bool]$RunGradle = $true,

	[bool]$CleanTargetAppDir = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step {
	param([string]$Message)
	Write-Host ""
	Write-Host "[STEP] $Message" -ForegroundColor Cyan
}

function Write-Info {
	param([string]$Message)
	Write-Host "[INFO] $Message" -ForegroundColor DarkGray
}

function Resolve-AbsolutePath {
	param([string]$Path)

	if ([string]::IsNullOrWhiteSpace($Path)) {
		return $Path
	}

	if ([System.IO.Path]::IsPathRooted($Path)) {
		return [System.IO.Path]::GetFullPath($Path)
	}

	return [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location).Path -ChildPath $Path))
}

function Assert-PathExists {
	param(
		[string]$Path,
		[string]$Label
	)

	if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
		throw "$Label not found: $Path"
	}
}

function Get-ManifestValue {
	param(
		[string]$ManifestPath,
		[string]$Key
	)

	$content = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
	$pattern = '"' + [regex]::Escape($Key) + '"\s*:\s*"([^"]+)"'
	$match = [regex]::Match($content, $pattern)

	if ($match.Success) {
		return $match.Groups[1].Value
	}

	return $null
}

function Invoke-NativeCommand {
	param(
		[string]$FilePath,
		[string[]]$Arguments,
		[string]$WorkingDirectory
	)

	$commandLine = @($FilePath) + $Arguments
	Write-Info ($commandLine -join " ")

	$originalLocation = (Get-Location).Path

	try {
		if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
			Set-Location -LiteralPath $WorkingDirectory
		}

		& $FilePath @Arguments

		if ($LASTEXITCODE -ne 0) {
			throw "Command failed with exit code: $LASTEXITCODE"
		}
	}
	finally {
		Set-Location -LiteralPath $originalLocation
	}
}

function Ensure-HBuilderXRunning {
	param(
		[string]$ExecutablePath,
		[bool]$AutoStart,
		[int]$StartupWaitSeconds
	)

	$process = Get-Process -Name "HBuilderX" -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($null -ne $process) {
		Write-Info ("HBuilderX is already running. PID: {0}" -f $process.Id)
		return
	}

	if (-not $AutoStart) {
		throw "HBuilderX is not running. Set -AutoStartHBuilderX:`$true or start it manually."
	}

	Assert-PathExists -Path $ExecutablePath -Label "HBuilderX executable"

	Write-Step "Start HBuilderX"
	Write-Info $ExecutablePath
	Start-Process -FilePath $ExecutablePath | Out-Null

	$deadline = (Get-Date).AddSeconds($StartupWaitSeconds)
	do {
		Start-Sleep -Milliseconds 500
		$process = Get-Process -Name "HBuilderX" -ErrorAction SilentlyContinue | Select-Object -First 1
	} while ($null -eq $process -and (Get-Date) -lt $deadline)

	if ($null -eq $process) {
		throw "HBuilderX did not start within the expected time window."
	}

	Write-Info ("HBuilderX started. PID: {0}" -f $process.Id)
	Start-Sleep -Seconds 2
}

function Ensure-JavaRuntime {
	param([string]$JavaHome)

	if (-not [string]::IsNullOrWhiteSpace($JavaHome)) {
		$resolvedJavaHome = Resolve-AbsolutePath -Path $JavaHome
		Assert-PathExists -Path $resolvedJavaHome -Label "JavaHome"

		$javaExe = Join-Path -Path $resolvedJavaHome -ChildPath "bin/java.exe"
		Assert-PathExists -Path $javaExe -Label "java.exe"

		$env:JAVA_HOME = $resolvedJavaHome
		$javaBin = Join-Path -Path $resolvedJavaHome -ChildPath "bin"
		if (-not ($env:Path -split ";" | Where-Object { $_ -eq $javaBin })) {
			$env:Path = "{0};{1}" -f $javaBin, $env:Path
		}

		Write-Info ("JAVA_HOME: {0}" -f $env:JAVA_HOME)
		return
	}

	if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
		Write-Info ("Use existing JAVA_HOME: {0}" -f $env:JAVA_HOME)
		return
	}

	throw "JAVA_HOME is required for Gradle. Pass -JavaHome or configure it in the environment."
}

function Resolve-AppResourcePath {
	param(
		[string]$ProjectPath,
		[string]$AppId,
		[string]$OverridePath
	)

	if (-not [string]::IsNullOrWhiteSpace($OverridePath)) {
		$resolvedOverride = Resolve-AbsolutePath -Path $OverridePath
		Assert-PathExists -Path $resolvedOverride -Label "Custom resource directory"
		return $resolvedOverride
	}

	$defaultPath = Join-Path -Path $ProjectPath -ChildPath ("unpackage/resources/{0}" -f $AppId)
	if (Test-Path -LiteralPath $defaultPath) {
		return $defaultPath
	}

	$resourceRoot = Join-Path -Path $ProjectPath -ChildPath "unpackage/resources"
	Assert-PathExists -Path $resourceRoot -Label "uni-app resource root"

	$fallback = Get-ChildItem -LiteralPath $resourceRoot -Directory |
		Sort-Object -Property LastWriteTime -Descending |
		Select-Object -First 1

	if ($null -eq $fallback) {
		throw "No app resource directory was found under unpackage/resources."
	}

	Write-Info ("AppId-specific directory not found. Fallback to latest resource directory: {0}" -f $fallback.FullName)
	return $fallback.FullName
}

function Find-ArtifactsByPattern {
	param(
		[string]$ModulePath,
		[string]$OutputRoot,
		[string]$Pattern
	)

	$searchRoots = @()

	foreach ($candidate in @(
		$OutputRoot,
		(Join-Path -Path $ModulePath -ChildPath "build/outputs"),
		(Join-Path -Path $ModulePath -ChildPath "release")
	)) {
		if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate) -and -not ($searchRoots -contains $candidate)) {
			$searchRoots += $candidate
		}
	}

	if ($searchRoots.Count -eq 0) {
		return @()
	}

	$artifacts = foreach ($root in $searchRoots) {
		Get-ChildItem -LiteralPath $root -Recurse -File -Filter $Pattern -ErrorAction SilentlyContinue
	}

	return $artifacts |
		Group-Object -Property FullName |
		ForEach-Object { $_.Group[0] } |
		Sort-Object -Property LastWriteTime -Descending
}

try {
	$HBuilderXCliPath = Resolve-AbsolutePath -Path $HBuilderXCliPath
	$HBuilderXExecutablePath = Resolve-AbsolutePath -Path $HBuilderXExecutablePath
	$UniAppProjectPath = Resolve-AbsolutePath -Path $UniAppProjectPath
	$AndroidStudioProjectPath = Resolve-AbsolutePath -Path $AndroidStudioProjectPath

	Assert-PathExists -Path $HBuilderXCliPath -Label "HBuilderX CLI"
	Assert-PathExists -Path $UniAppProjectPath -Label "uni-app project directory"
	Assert-PathExists -Path $AndroidStudioProjectPath -Label "Android Studio project directory"
	$androidModulePath = Join-Path -Path $AndroidStudioProjectPath -ChildPath $AndroidAppModuleName
	Assert-PathExists -Path $androidModulePath -Label "Android app module directory"

	if ([string]::IsNullOrWhiteSpace($UniAppProjectName)) {
		$UniAppProjectName = Split-Path -Path $UniAppProjectPath -Leaf
	}

	if ([string]::IsNullOrWhiteSpace($AssetsAppsRoot)) {
		$AssetsAppsRoot = Join-Path -Path $AndroidStudioProjectPath -ChildPath ("{0}/src/main/assets/apps" -f $AndroidAppModuleName)
	}
	else {
		$AssetsAppsRoot = Resolve-AbsolutePath -Path $AssetsAppsRoot
	}

	if ([string]::IsNullOrWhiteSpace($GradleExecutable)) {
		$GradleExecutable = Join-Path -Path $AndroidStudioProjectPath -ChildPath "gradlew.bat"
	}
	else {
		$GradleExecutable = Resolve-AbsolutePath -Path $GradleExecutable
	}

	if ([string]::IsNullOrWhiteSpace($OutputDir)) {
		$OutputDir = [Environment]::GetFolderPath("Desktop")
	}
	else {
		$OutputDir = Resolve-AbsolutePath -Path $OutputDir
	}

	$manifestPath = Join-Path -Path $UniAppProjectPath -ChildPath "manifest.json"
	Assert-PathExists -Path $manifestPath -Label "manifest.json"

	if ([string]::IsNullOrWhiteSpace($UniAppAppId)) {
		$UniAppAppId = Get-ManifestValue -ManifestPath $manifestPath -Key "appid"
	}

	if ([string]::IsNullOrWhiteSpace($UniAppAppId)) {
		throw "Unable to resolve appid from manifest.json. Pass -UniAppAppId explicitly."
	}

	Write-Step "Resolved configuration"
	Write-Info ("UniAppProjectPath: {0}" -f $UniAppProjectPath)
	Write-Info ("UniAppProjectName: {0}" -f $UniAppProjectName)
	Write-Info ("PublishPlatform: {0}" -f $PublishPlatform)
	Write-Info ("UniAppAppId: {0}" -f $UniAppAppId)
	Write-Info ("AndroidStudioProjectPath: {0}" -f $AndroidStudioProjectPath)
	Write-Info ("AndroidAppModuleName: {0}" -f $AndroidAppModuleName)
	Write-Info ("AssetsAppsRoot: {0}" -f $AssetsAppsRoot)
	Write-Info ("GradleExecutable: {0}" -f $GradleExecutable)
	Write-Info ("GradleTask: {0}" -f $GradleTask)
	Write-Info ("HBuilderXExecutablePath: {0}" -f $HBuilderXExecutablePath)
	Write-Info ("JavaHome: {0}" -f $JavaHome)
	Write-Info ("OutputDir: {0}" -f $OutputDir)

	Ensure-HBuilderXRunning -ExecutablePath $HBuilderXExecutablePath -AutoStart $AutoStartHBuilderX -StartupWaitSeconds $HBuilderXStartupWaitSeconds
	Ensure-JavaRuntime -JavaHome $JavaHome

	if ($OpenProjectBeforePublish) {
		Write-Step "Open project in HBuilderX"
		Invoke-NativeCommand -FilePath $HBuilderXCliPath -Arguments @(
			"project",
			"open",
			"--path",
			$UniAppProjectPath
		) -WorkingDirectory $null
	}

	if ($RunPublish) {
		Write-Step "Publish uni-app app resources"

		$publishArguments = @("publish")
		if ($PublishPlatform -ieq "APP") {
			$publishArguments += @("--platform", "APP")
		}
		else {
			$publishArguments += $PublishPlatform
		}

		$publishArguments += @(
			"--type",
			"appResource",
			"--project",
			$UniAppProjectName
		)

		Invoke-NativeCommand -FilePath $HBuilderXCliPath -Arguments $publishArguments -WorkingDirectory $null
	}

	$sourceAppDir = Resolve-AppResourcePath -ProjectPath $UniAppProjectPath -AppId $UniAppAppId -OverridePath $ResourceRootOverride
	$targetAppDir = Join-Path -Path $AssetsAppsRoot -ChildPath $UniAppAppId

	Write-Step "Resolve resource directories"
	Write-Info ("SourceAppDir: {0}" -f $sourceAppDir)
	Write-Info ("TargetAppDir: {0}" -f $targetAppDir)

	if ($RunCopy) {
		Write-Step "Copy app resources into Android shell project"
		New-Item -ItemType Directory -Path $AssetsAppsRoot -Force | Out-Null

		if ($CleanTargetAppDir -and (Test-Path -LiteralPath $targetAppDir)) {
			Write-Info ("Remove previous directory: {0}" -f $targetAppDir)
			Remove-Item -LiteralPath $targetAppDir -Recurse -Force
		}

		Copy-Item -LiteralPath $sourceAppDir -Destination $AssetsAppsRoot -Recurse -Force
	}

	if ($RunGradle) {
		Write-Step "Run Gradle build"
		Assert-PathExists -Path $GradleExecutable -Label "Gradle wrapper"

		$gradleTaskToRun = if ($GradleTask -like ":*") {
			$GradleTask
		}
		else {
			":{0}:{1}" -f $AndroidAppModuleName, $GradleTask
		}

		$gradleArguments = @($gradleTaskToRun) + $GradleExtraArgs
		Invoke-NativeCommand -FilePath $GradleExecutable -Arguments $gradleArguments -WorkingDirectory $AndroidStudioProjectPath

		$outputRoot = Join-Path -Path $androidModulePath -ChildPath "build/outputs"
		$artifactPattern = if ($GradleTask -match "bundle") { "*.aab" } else { "*.apk" }
		$artifacts = Find-ArtifactsByPattern -ModulePath $androidModulePath -OutputRoot $outputRoot -Pattern $artifactPattern

		Write-Step "Build artifacts"
		if ($artifacts.Count -gt 0) {
			$artifacts |
				Select-Object -First 5 |
				ForEach-Object {
					Write-Host $_.FullName -ForegroundColor Green
				}
		}
		else {
			Write-Info ("Gradle finished but no artifact was found under: {0}" -f $outputRoot)
		}

		if ($CopyLatestApkToOutputDir) {
			$apkArtifacts = Find-ArtifactsByPattern -ModulePath $androidModulePath -OutputRoot $outputRoot -Pattern "*.apk"

			Write-Step "Copy latest APK"
			if ($apkArtifacts.Count -gt 0) {
				New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

				$outputApkName = "{0}.apk" -f (Get-Date -Format $OutputApkNameFormat)
				$outputApkPath = Join-Path -Path $OutputDir -ChildPath $outputApkName

				Copy-Item -LiteralPath $apkArtifacts[0].FullName -Destination $outputApkPath -Force
				Write-Host $outputApkPath -ForegroundColor Green
			}
			else {
				Write-Info "No APK found to copy. If you built a bundle task, this is expected."
			}
		}
	}

	Write-Step "Done"
	Write-Host "All steps completed successfully." -ForegroundColor Green
}
catch {
	Write-Host ""
	Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
	exit 1
}
