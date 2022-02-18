## Inspired by 
* [@djkaty](https://github.com/djkaty)'s [IL2CPP Reverse Engineering Part 1: Hello World and the IL2CPP Toolchain](https://katyscode.wordpress.com/2020/06/24/il2cpp-part-1/) article
* [@jacksondunstan](https://github.com/jacksondunstan)'s [How to See What C# Turns Into](https://www.jacksondunstan.com/articles/4661) article

## For whom
For Unity programmers and Unity performance engineers.

## Aim
This tool aimed to see literally "What C# Turns Into" but without Unity compilation time overhead for fast proving or disproving your performance assumptions.

## How to use

Based on [il2cpp.ps1](https://github.com/djkaty/Il2CppInspector/blob/master/Il2CppTests/il2cpp.ps1) but rewritten for my purposes and wishes. 
Read script yourself for more understanding. Or read the articles above.

1. Clone repo or just download the [il2cpp.ps1](https://github.com/Brown2Fox/Il2CppTests/blob/master/il2cpp.ps1) file to directory you want
2. Create `unity_search_path.txt` and paste Unity installation directory path (usually `C:\Program Files\Unity\Hub\Editor`) to it _(Optional, but recommended)_
3. Create `android_ndk_search_path.txt` and paste Android NDK directory path to it _(Optional, but recommended)_
4. Create directory `TestSources` and place your `.cs` files into it
5. Call script with required parameters in PowerShell
```
il2cpp.ps1 [sourceFileWithoutExtension,...] [unityVersionOrFullPath] [ndkVersionOrFullPath] [target,...]
``` 
6. It should create next dirs:
    1. `TestAssemblies` - contains compiled dll's
    2. `TestBinaries` - contains compiled binary for specified targets (x86, x64, armv7 or arm64)
    3. `TestCpp` - contains compiled `.cpp` files

#### Usage example

1. Suppose in file `unity_search_path.txt` specified `C:\Program Files\Unity\Hub\Editor` path and that path contains `2019.4.33f` directory (with installed Unity, ofc)
2. Suppose in file `android_ndk_search_path.txt` specified `C:\Users\Brown2Fox\DevTools\Android\Ndk` path and that path contains `android-ndk-r19c` directory (with installed NDK, ofc)
3. Suppose directory `TestSources` contains file `MyTest.cs`
3. Then we call in PowerShell command `il2cpp.ps1 MyTest 2019.4.33* *r19c armv7` and get the result

## Some other notes

* You can specify no target (x86, x64, armv7 or arm64) if you interested only in cpp part 
* Remove `UnityEngine.CoreModule.dll` from `$csrefs` var in script if you want test simple C# without Unity's stuff (and for speeding up binary compilation time)
* Resulting cpp files can varies depending on `csc` and `il2cpp` compilation options
  * By default for `csc` specified `-optimize+` option and for `il2cpp` specified `--configuration=ReleasePlus` option
  * Tweak script for change this behavior
