:: Name:     build.cmd
:: Author:   daniel@cazzulino.com
:: Purpose:  Provides a quick way to run a local build of build.proj 
::           for the current MSBuild version, which depends on the 
::           developer command prompt being used.
::
::           Optionally, it can be invoked passing msbuild parameters, 
::           like: build.cmd /v:detailed /t:Rebuild
::
::           Running this batch file is optional, as a shortcut to 
::           just running MSBuild for build.proj
::
:: Revision: Jun 2015 - Added nuget download/restore support.
::           May 2015 - Reworked version, comments, etc.

@ECHO OFF
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION
SET CACHED_NUGET=%LocalAppData%\NuGet\NuGet.exe
PUSHD "%~dp0" > nul

:: Determine if MSBuild can be located. Allows for a better error message below.
where msbuild > %TEMP%\msbuild.txt
set /p msb=<%TEMP%\msbuild.txt

IF "%msb%"=="" (
    echo Please run %~n0 from a Visual Studio Developer Command Prompt.
    exit /b -1
)

IF EXIST %CACHED_NUGET% goto copynuget
echo Downloading latest version of NuGet.exe...
IF NOT EXIST %LocalAppData%\NuGet md %LocalAppData%\NuGet
@powershell -NoProfile -ExecutionPolicy unrestricted -Command "$ProgressPreference = 'SilentlyContinue'; (New-Object System.Net.WebClient).DownloadFile('http://nuget.org/nuget.exe', '%CACHED_NUGET%')"

:copynuget
IF EXIST .nuget\nuget.exe goto restore
md .nuget
copy %CACHED_NUGET% .nuget\nuget.exe > nul

:restore
IF NOT EXIST packages.config goto run
.nuget\NuGet.exe install packages.config -OutputDirectory .nuget\packages -ExcludeVersion

:run
"%msb%" %~dp0\build.proj /nologo /v:minimal /maxcpucount /nr:true %1 %2 %3 %4 %5 %6 %7 %8 %9

POPD > nul
ENDLOCAL
ECHO ON