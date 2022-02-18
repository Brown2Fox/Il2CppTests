# Copyright 2019-2021 Katy Coe - http://www.djkaty.com - https://github.com/djkaty
# All rights reserved.

# Compile the specified .cs files in TestSources to produce a .NET assembly DLL, the transpiled C++ source code and an IL2CPP binary for each

# Requires Unity >= 2017.1.0f3 or later 
# Requires Windows Standalone IL2CPP support, Android IL2CPP support (optional)
# Requires Android NDK for Android test builds (https://developer.android.com/ndk/downloads)

# Tested with Unity 2017.1.0f3 - 2021.1.0a6

# Tip: To compile a chosen source file for every installed version of Unity, try:
# gci $env:ProgramFiles\Unity\Hub\Editor | % { ./il2cpp.ps1 <source-file-without-extension> $_.Name }

param (
	[switch] $help,

	# Which source files in TestSources to generate aseemblies, C++ and IL2CPP binaries for (comma-separated, without .cs extension)
	[string[]] $assemblies = "*",

	# Which Unity version to use; uses the latest installed if not specified
	# Accepts wildcards and always sorts from highest to lowest version eg.:
	# 2018* will select the latest Unity 2018 install, 2019.1.* will select the latest 2019.1 install etc.
	# You can also specify a full path to a Unity install folder
	[string] $unityVersion = "*",
	[string] $ndkVersion = "*",
	[string[]] $targets
)

Write-Output "Universal IL2CPP Build Utility"
Write-Output "(c) 2019-2021 Katy Coe - www.djkaty.com - www.github.com/djkaty"
Write-Output ""

if ($help) {
	Write-Output "Usage: il2cpp.ps1 [TestSources-source-file-without-extension,...] [unityVersionOrFullPath] [ndkVersionOrFullPath] [x86|x64|armv7|arm64]"
	Exit
}

$errorActionPreference = "SilentlyContinue"

# Function to compare two Unity versions
function Compare-UnityVersions {
	param (
		[string] $left,
		[string] $right
	)
	$rgx = '^(?<major>[0-9]{1,4})\.(?<minor>[0-6])\.(?<build>[0-9]{1,2}).*$'
	if ($left -notmatch $rgx) {
		Write-Error "Invalid Unity version number or the specified Unity version is not installed"
		Exit
	}
	$leftVersion = $Matches
	if ($right -notmatch $rgx) {
		Write-Error "Invalid Unity version number or the specified Unity version is not installed"
		Exit
	}
	$rightVersion = $Matches

	if ($leftVersion.major -ne $rightVersion.major) {
		return $leftVersion.major - $rightVersion.major
	}
	if ($leftVersion.minor -ne $rightVersion.minor) {
		return $leftVersion.minor - $rightVersion.minor
	}
	$leftVersion.build - $rightVersion.build
}

# If supplied Unity version is a path, use it, otherwise assume default path from version number alone
if ($unityVersion -match "[\\/]") {
	$unityFolder = $unityVersion
} else {
	# The introduction of Unity Hub changed the base path of the Unity editor
	$unitySearchPath = Get-Item -Path .\unity_search_path.txt | Get-Content -Tail 1
	$unityFolder = (Get-Item "$unitySearchPath\$unityVersion").FullName
}


# Path to latest installed version of Unity
$unityEditorPath = (Get-Item "$unityFolder\Editor").FullName
$unityPath = "$unityEditorPath\Data"
$unityEngineManaged = "$unityPath\Managed\UnityEngine"

# A silent exception will be thrown and the variable will not be re-assigned.
# Look for Unity Roslyn installs
$roslynPath = (Get-Item "$unityPath\Tools\Roslyn\").FullName
$csc = "$roslynPath\csc.exe"


# Path to il2cpp.exe
# For Unity <= 2019.2.21f1, il2cpp\build\il2cpp.exe
# For Unity >= 2019.3.0f6, il2cpp\build\deploy\net471\il2cpp.exe
# For Unity >= 2020.2.0b2-ish, il2cpp\build\deploy\netcoreapp3.1\il2cpp.exe
$il2cpp = (Get-ChildItem "$unityPath\il2cpp\build" -Recurse -Filter "il2cpp.exe")[0].FullName

# Path to bytecode stripper
$stripper = (Get-ChildItem "$unityPath\il2cpp\build" -Recurse -Filter "UnityLinker.exe")[0].FullName

# Determine the actual Unity version
$actualUnityVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo("$unityEditorPath\Unity.exe").FileVersion

# Enable Write-Error before calling Compare-UnityVersions
$errorActionPreference = "Continue"

# Path to mscorlib.dll
# For Unity <= 2018.1.9f2, Mono\lib\mono\2.0\... (but also has the MonoBleedingEdge path which is incompatible)
# For Unity >= 2018.2.0f2, MonoBleedingEdge\lib\mono\unityaot\... (but some also have the mono path which is incompatible)
$monoManaged = "$unityPath\Mono\lib\mono\2.0"
if ((Compare-UnityVersions $actualUnityVersion 2018.2.0) -ge 0) {
	$monoManaged = "$unityPath\MonoBleedingEdge\lib\mono\unityaot"
}

# For Unity >= 2020.1.0f1, we need baselib
if ($actualUnityVersion -and (Compare-UnityVersions $actualUnityVersion 2020.1.0) -ge 0) {
	$baselibX64 = $unityPath + '\PlaybackEngines\windowsstandalonesupport\Variations\win64_nondevelopment_il2cpp'
	if (Test-Path -Path $baselibX64 -PathType container) {
		$baselibX64Arg = "--baselib-directory=$baselibX64"
	}

	$baselibX86 = $unityPath + '\PlaybackEngines\windowsstandalonesupport\Variations\win32_nondevelopment_il2cpp'
	if (Test-Path -Path $baselibX86 -PathType container) {
		$baselibX86Arg = "--baselib-directory=$baselibX86"
	}

	$baselibARM64 = $unityPath + '\PlaybackEngines\AndroidPlayer\Variations\il2cpp\Release\StaticLibs\arm64-v8a'
	if (Test-Path -Path $baselibARM64 -PathType container) {
		$baselibARM64Arg = "--baselib-directory=$baselibARM64"
	}

	$baselibARMv7 = $unityPath + '\PlaybackEngines\AndroidPlayer\Variations\il2cpp\Release\StaticLibs\armeabi-v7a'
	if (Test-Path -Path $baselibARMv7 -PathType container) {
		$baselibARMv7Arg = "--baselib-directory=$baselibARMv7"
	}
}

# Path to the Android NDK
# Different Unity versions require specific NDKs, see the section Change the NDK at:
# The NDK can also be installed standalone without AndroidPlayer
# https://docs.unity3d.com/2019.1/Documentation/Manual/android-sdksetup.html
$androidPlayer = $unityPath + '\PlaybackEngines\AndroidPlayer'

if ($ndkVersion -match "[\\/]") {
	$androidNdk = $ndkVersion
} else {
	# The introduction of Unity Hub changed the base path of the Unity editor
	$ndkSearchPath = Get-Item -Path .\android_ndk_search_path.txt | Get-Content -Tail 1
	$androidNdk  = (Get-Item "$ndkSearchPath\$ndkVersion").FullName
}

$androidBuildEnabled = $True

# Check that everything is installed
if (!$csc) {
	Write-Error "Could not find C# compiler csc.exe - aborting"
	Exit
}

if (!$androidNdk -or !(Test-Path -Path $androidNdk -PathType container)) {
	Write-Output "Could not find Android NDK"
	$androidBuildEnabled = $False
}

if (!$il2cpp) {
	Write-Error "Could not find Unity IL2CPP build support - aborting"
	Exit
}

if (!$stripper) {
	Write-Error "Could not find Unity IL2CPP bytecode stripper - aborting"
	Exit
}

if (!$androidPlayer -or !(Test-Path -Path $androidPlayer -PathType container)) {
	Write-Output "Could not find Unity Android build support at '$androidPlayer'"
	$androidBuildEnabled = $False
}

Write-Output "Using C# compiler at '$csc'"
Write-Output "Using Unity installation at '$unityPath'"
Write-Output "Using IL2CPP toolchain at '$il2cpp'"
Write-Output "Using Unity mscorlib assembly at '$mscorlib'"

if ($androidBuildEnabled) {
	Write-Output "Using Android player at '$androidPlayer'"
	Write-Output "Using Android NDK at '$androidNdk'"
} else {
	Write-Output "Android build is disabled due to missing components"
}

Write-Output "Targeted Unity version: $actualUnityVersion"
Write-Output ""

# Workspace paths
$src = "$PSScriptRoot/TestSources"
$asm = "$PSScriptRoot/TestAssemblies"
$cpp = "$PSScriptRoot/TestCpp"
$bin = "$PSScriptRoot/TestBinaries"

# We try to make the arguments as close as possible to a real Unity build
# "--lump-runtime-library" was added to reduce the number of C++ files generated by UnityEngine (Unity 2019)
# "--disable-runtime-lumping" replaced the above (Unity 2019.3)
$cppArg =		'--convert-to-cpp', '-emit-null-checks', '--enable-array-bounds-check'

$compileArg =	'--compile-cpp', '--libil2cpp-static', '--configuration=ReleasePlus', `
				"--map-file-parser=$unityPath\il2cpp\MapFileParser\MapFileParser", '--enable-debugger', '--profiler-report', '--forcerebuild'			


if ((Compare-UnityVersions $actualUnityVersion 2018.2.0f2) -ge 0) {
	$cppArg +=		'--dotnetprofile="unityaot"'
	$compileArg +=	'--dotnetprofile="unityaot"'
}

# Prepare output folders
New-Item -ErrorAction Ignore -Type Directory $asm, $bin | Out-Null

# Compile all specified .cs files in TestSources
Write-Output "Compiling source code..."

$csrefs = "$monoManaged\mscorlib.dll,$unityEngineManaged\UnityEngine.CoreModule.dll"

$assemblies | ForEach-Object {
	$cs = Get-Item $src/$_.cs

	Write-Output "$($cs.Name) -> $($cs.BaseName).dll"

	& $csc -target:library -optimize+ -reference:$csrefs -nologo -unsafe -langversion:latest -out:$asm/$($cs.BaseName).dll $cs
	
	if ($LastExitCode -ne 0) {
		Write-Error "Compilation error - aborting"
		Exit
	}
}


if ((Compare-UnityVersions $actualUnityVersion 2018.2.0f2) -ge 0) {
	$stripperAdditionalArguments = "--dotnetruntime=il2cpp", "--dotnetprofile=unityaot", "--use-editor-options"
}

# Strip each assembly of unnecessary code to reduce compile time
$assemblies | ForEach-Object {
	$dll = Get-Item $asm/$_.dll
	$name = $dll.Name
	Write-Output "Running bytecode stripper on $name..."

	& $stripper	--out=$asm/$($dll.BaseName)-stripped --i18n=none --core-action=link `
				--include-assembly=$dll,$csrefs $stripperAdditionalArguments
}


# Transpile all of the DLLs to C++
# We split this up from the binary compilation phase to avoid unnecessary DLL -> C++ transpiles for the same application
$assemblies | ForEach-Object {
	$dll = Get-Item $asm/$_.dll
	$baseName = $dll.BaseName
	Write-Output "Converting assembly $($dll.Name) to C++..."
	Remove-Item -Force -Recurse $cpp/$baseName
	& $il2cpp $cppArg --generatedcppdir=$cpp/$($dll.BaseName) --assembly=$asm/$($dll.BaseName)-stripped/$($dll.Name) --copy-level=None
}

# Run IL2CPP on all generated assemblies for both x86 and ARM
# Earlier builds of Unity included mscorlib.dll automatically; in current versions we must specify its location
function Invoke-Il2CppBuild {
	param (
		[string] $platform,
		[string] $arch,
		[string] $name,
		[string[]] $additionalArgs
	)

	# Determine target name
	$prefix = if ($arch -eq 'x86' -or $arch -eq 'x64') {'GameAssembly-'}
	$ext = if ($arch -eq 'x86' -or $arch -eq 'x64') {"dll"} else {"so"}
	$targetBaseName = "$prefix$name-$arch"

	Write-Output "Running il2cpp compiler for $targetBaseName ($platform/$arch)..."

	# Compile
	New-Item -ErrorAction Ignore -Type Directory $bin/$targetBaseName
	New-Item -ErrorAction Ignore -Type Directory $bin/$targetBaseName/cache

	& $il2cpp $compileArg $additionalArgs --platform=$platform --architecture=$arch `
				--outputpath=$bin/$targetBaseName/$targetBaseName.$ext `
				--generatedcppdir=$cpp/$name `
				--cachedirectory=$bin/$targetBaseName/cache 

	if ($LastExitCode -ne 0) {
		Write-Error "IL2CPP error - aborting"
		Exit
	}
}

if ($targets) {
	# Generate build for each target platform and architecture
	$assemblies | ForEach-Object {
		$dll = Get-Item "$asm/$_.dll"
		# x86
		if ($targets -match "x86") {
			Invoke-Il2CppBuild WindowsDesktop x86 $dll.BaseName $baselibX86Arg
		}
		
		# x64
		if ($targets -match "x64") {
			Invoke-Il2CppBuild WindowsDesktop x64 $dll.BaseName $baselibX64Arg
		}

		# ARMv7
		if ($androidBuildEnabled -and ($targets -match "armv7")) {
			Invoke-Il2CppBuild Android ARMv7 $dll.BaseName $baselibARMv7Arg, `
						--additional-include-directories=$androidPlayer/Tools/bdwgc/include, `
						--additional-include-directories=$androidPlayer/Tools/libil2cpp/include, `
						--tool-chain-path=$androidNdk
		}

		# ARMv8 / A64
		if ($androidBuildEnabled -and ($targets -match "arm64")) {
			Invoke-Il2CppBuild Android ARM64 $dll.BaseName $baselibARM64Arg, `
						--additional-include-directories=$androidPlayer/Tools/bdwgc/include, `
						--additional-include-directories=$androidPlayer/Tools/libil2cpp/include, `
						--tool-chain-path=$androidNdk
		}
	}
}