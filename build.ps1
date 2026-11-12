#Requires -Version 5.1
<#
.SYNOPSIS
    Builds and signs EdgeToEdgeCutout.apk without Gradle using the pinned SDK/R8 toolchain.
#>
param(
    [string]$ToolsDir = ''
)

$ErrorActionPreference = 'Stop'

$Root = $PSScriptRoot
if (-not $ToolsDir) {
    $localTools = Join-Path $Root 'tools'
    $parentTools = Join-Path (Split-Path -Parent $Root) 'tools'
    if (Test-Path -LiteralPath (Join-Path $localTools 'r8-current.jar')) {
        $ToolsDir = $localTools
    } elseif (Test-Path -LiteralPath (Join-Path $parentTools 'r8-current.jar')) {
        $ToolsDir = $parentTools
    } else {
        throw "Toolchain not found. Run .\bootstrap.ps1 first or pass -ToolsDir."
    }
}

$BuildTools = Join-Path $ToolsDir 'buildtools34\android-14'
$AndroidJar = Join-Path $ToolsDir 'platform33\android-33-ext5\android.jar'
$XposedJar = Join-Path $ToolsDir 'xposed-api82.jar'
$R8Jar = Join-Path $ToolsDir 'r8-current.jar'
$Aapt2 = Join-Path $BuildTools 'aapt2.exe'
$ZipAlign = Join-Path $BuildTools 'zipalign.exe'
$ApkSignerJar = Join-Path $BuildTools 'lib\apksigner.jar'

foreach ($req in @($AndroidJar, $XposedJar, $R8Jar, $Aapt2, $ZipAlign, $ApkSignerJar)) {
    if (-not (Test-Path -LiteralPath $req)) {
        throw "Missing required tool file: $req (run .\bootstrap.ps1)"
    }
}

function Assert-ExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step failed with exit code $LASTEXITCODE"
    }
}

$BuildDir = Join-Path $Root 'build'
$ObjDir = Join-Path $BuildDir 'obj'
$GenDir = Join-Path $BuildDir 'gen'
$DexDir = Join-Path $BuildDir 'dex'
$ResZip = Join-Path $BuildDir 'res.zip'
$ClassesJar = Join-Path $BuildDir 'classes.jar'
$UnsignedApk = Join-Path $BuildDir 'unsigned.apk'
$AlignedApk = Join-Path $BuildDir 'aligned.apk'
$SignedApk = Join-Path $BuildDir 'EdgeToEdgeCutout.apk'

if (Test-Path -LiteralPath $BuildDir) {
    Remove-Item -Recurse -Force -LiteralPath $BuildDir
}
New-Item -ItemType Directory -Force -Path $ObjDir, $GenDir, $DexDir | Out-Null

# 1. Compile Android resources and link manifest + assets
& $Aapt2 compile --dir (Join-Path $Root 'res') -o $ResZip
Assert-ExitCode 'aapt2 compile'

& $Aapt2 link `
    -I $AndroidJar `
    --manifest (Join-Path $Root 'AndroidManifest.xml') `
    -A (Join-Path $Root 'assets') `
    --java $GenDir `
    -o $UnsignedApk `
    $ResZip
Assert-ExitCode 'aapt2 link'

# 2. Compile Java sources (UTF-8, targeting Java 11 bytecode)
$JavaFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $Root 'src') -Recurse -Filter '*.java' | ForEach-Object FullName
    Get-ChildItem -LiteralPath $GenDir -Recurse -Filter '*.java' | ForEach-Object FullName
)
& javac --release 11 -encoding UTF-8 -classpath "$AndroidJar;$XposedJar" -d $ObjDir @JavaFiles
Assert-ExitCode 'javac'

& jar cf $ClassesJar -C $ObjDir .
Assert-ExitCode 'jar cf'

# 3. Compile bytecode to classes.dex using pinned R8/D8
& java -cp $R8Jar com.android.tools.r8.D8 `
    --min-api 30 `
    --lib $AndroidJar `
    --classpath $XposedJar `
    --output $DexDir `
    $ClassesJar
Assert-ExitCode 'D8'

# 4. Package classes.dex into APK and zipalign
& jar uf $UnsignedApk -C $DexDir classes.dex
Assert-ExitCode 'jar uf classes.dex'

& $ZipAlign -f -p 4 $UnsignedApk $AlignedApk
Assert-ExitCode 'zipalign'

# 5. Persistent local signing keystore (kept outside build/ so updates keep the same signature)
$LocalDir = Join-Path $Root '.local'
New-Item -ItemType Directory -Force -Path $LocalDir | Out-Null
$Keystore = Join-Path $LocalDir 'build-signing.jks'
$PasswordFile = Join-Path $LocalDir 'signing-password.txt'

if (-not $env:EDGETOEDGE_SIGNING_PASSWORD) {
    if (Test-Path -LiteralPath $PasswordFile) {
        $env:EDGETOEDGE_SIGNING_PASSWORD = (Get-Content -LiteralPath $PasswordFile -Raw).Trim()
    } else {
        $env:EDGETOEDGE_SIGNING_PASSWORD = [guid]::NewGuid().ToString('N')
        Set-Content -LiteralPath $PasswordFile -Value $env:EDGETOEDGE_SIGNING_PASSWORD -NoNewline
    }
}

if (-not (Test-Path -LiteralPath $Keystore)) {
    & keytool -genkeypair `
        -keystore $Keystore `
        -storepass:env EDGETOEDGE_SIGNING_PASSWORD `
        -keypass:env EDGETOEDGE_SIGNING_PASSWORD `
        -alias edgetoedge-cutout `
        -keyalg RSA `
        -keysize 2048 `
        -validity 3650 `
        -dname 'CN=EdgeToEdge Cutout Build,O=OpenSource,C=US' | Out-Null
    Assert-ExitCode 'keytool'
}

& java -jar $ApkSignerJar sign `
    --ks $Keystore `
    --ks-key-alias edgetoedge-cutout `
    --ks-pass env:EDGETOEDGE_SIGNING_PASSWORD `
    --key-pass env:EDGETOEDGE_SIGNING_PASSWORD `
    --out $SignedApk `
    $AlignedApk
Assert-ExitCode 'apksigner sign'

& java -jar $ApkSignerJar verify --verbose $SignedApk
Assert-ExitCode 'apksigner verify'

Get-Item -LiteralPath $SignedApk | Select-Object FullName, Length
