<#
This script builds libiconv,libxml2 and libxslt
#>
Param(
    [switch]$x64,
    [switch]$vs2008
)

Function ThrowIfError($exitCode, $module)
{
    if ($exitCode -ne 0)
    {
        throw "Cannot build: $module."
    }
}

$ErrorActionPreference = "Stop"
Import-Module Pscx

$x64Dir = If($x64) { "\x64" } Else { "" }
$distname = If($x64) { "win64" } Else { "win32" }
If($vs2008) { $distname = "vs2008.$distname" }
$vcvarsarch = If($x64) { "amd64" } Else { "x86" }
$vsver = If($vs2008) { "90" } Else { "140" }

Set-Location $PSScriptRoot

Import-VisualStudioVars -VisualStudioVersion $vsver -Architecture $vcvarsarch

if($vs2008) {
    Set-Location .\libiconv\MSVC9
    $vcarch = If($x64) { "x64" } Else {"Win32"}
    vcbuild libiconv_static\libiconv_static.vcproj "Release|$vcarch"
} else {
    Set-Location .\libiconv\MSVC14
    msbuild libiconv.sln /p:Configuration=Release /t:libiconv_static
}
ThrowIfError $LastExitCode "libiconv"
$iconvLib = Join-Path (pwd) libiconv_static$x64Dir\Release
$iconvInc = Join-Path (pwd) ..\source\include
Set-Location ..\..

Set-Location .\zlib
$p = Start-Process -NoNewWindow -Wait -PassThru nmake "-f win32/Makefile.msc zlib.lib"
ThrowIfError $p.ExitCode "zlib"
$zlibLib = (pwd)
$zlibInc = (pwd)
Set-Location ..

Set-Location .\libxml2\win32
cscript configure.js lib="$zlibLib;$iconvLib" include="$zlibInc;$iconvInc" vcmanifest=yes zlib=yes
$p = Start-Process -NoNewWindow -Wait -PassThru nmake libxmla
ThrowIfError $p.ExitCode "libxml"
$xmlLib = Join-Path (pwd) bin.msvc
$xmlInc = Join-Path (pwd) ..\include
Set-Location ..\..

Set-Location .\libxslt\win32
cscript configure.js lib="$zlibLib;$iconvLib;$xmlLib" include="$zlibInc;$iconvInc;$xmlInc" vcmanifest=yes zlib=yes
$p = Start-Process -NoNewWindow -Wait -PassThru nmake "libxslta libexslta"
ThrowIfError $p.ExitCode "libxslt"
Set-Location ..\..

# Pushed by Import-VisualStudioVars
Pop-EnvironmentBlock

# Bundle releases
Function BundleRelease($name, $lib, $inc)
{
    New-Item -ItemType Directory .\dist\$name

    New-Item -ItemType Directory .\dist\$name\lib
    Copy-Item -Recurse $lib .\dist\$name\lib
    Get-ChildItem -File -Recurse .\dist\$name\lib | Where{$_.Name -NotMatch ".(lib|pdb)$" } | Remove-Item

    New-Item -ItemType Directory .\dist\$name\include
    Copy-Item -Recurse $inc .\dist\$name\include
    Get-ChildItem -File -Recurse .\dist\$name\include | Where{$_.Name -NotMatch ".h$" } | Remove-Item

    Write-Zip  .\dist\$name .\dist\$name.zip
    Remove-Item -Recurse -Path .\dist\$name
}

if (Test-Path .\dist) { Remove-Item .\dist -Recurse }
New-Item -ItemType Directory .\dist

# lxml expects iconv to be called iconv, not libiconv
Dir $iconvLib\libiconv* | Copy-Item -Force -Destination {Join-Path $iconvLib ($_.Name -replace "libiconv","iconv") }

BundleRelease "iconv-1.14.$distname" (dir $iconvLib\iconv_a*) (dir $iconvInc\*)
BundleRelease "libxml2-2.9.5.$distname" (dir $xmlLib\*) (Get-Item $xmlInc\libxml)
BundleRelease "libxslt-1.1.30.$distname" (dir .\libxslt\win32\bin.msvc\*) (Get-Item .\libxslt\libxslt,.\libxslt\libexslt)
BundleRelease "zlib-1.2.11.$distname" (Get-Item .\zlib\*.*) (Get-Item .\zlib\zconf.h,.\zlib\zlib.h)
