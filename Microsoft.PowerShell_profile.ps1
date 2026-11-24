# https://deepwiki.com/PowerShell/PSReadLine/3.7-vi-mode
# https://terminalroot.com/customize-your-powershell-like-a-pro/
# https://www.windowscentral.com/software-apps/3-easy-ways-to-turn-windows-terminal-shells-from-drab-to-drip
# https://github.com/JanDeDobbeleer/oh-my-posh/
#
# see link above
# Import-Module -Name Terminal-Icons
# Package managers: winget, scoop, chocolatey
#   Recommend: chocolatey
#   Interesting read: https://www.xda-developers.com/chocolatey-vs-winget-vs-scoop/
#   Largest package repository: chocolatey
#   Ease of use and flexibility: scoop (no admin rights needed)
#   Winget is built-in on Windows 10 and 11, and preferably used to install chocolatey, scoop and other applications
#
# Required packages/software:
# oh my posh
# git
# nvim; win32, ripgrep
# ncspot
# fzf

# (env) variables

$env:DOTFILES="$env:USERPROFILE\dotfiles"
$env:GITCONFIG="$env:HOME\.gitconfig"
$env:SCRIPTS="$env:USERPROFILE\dotfiles\scripts"
$env:LOCAL="$env:USERPROFILE\.local"
$env:EDITOR="nvim"
# $env:CC="zig cc" TODO: install cl.exe?
# $cl = ...

# Newest installed PostgreSQL, if any
$postgreSQL=(Get-ChildItem "$env:ProgramFiles\PostgreSQL\*\bin" -Directory -ErrorAction SilentlyContinue |
    Sort-Object { [int]$_.Parent.Name } | Select-Object -Last 1).FullName
$env:NPM="$env:APPDATA\npm"
$pnpm="$env:LOCALAPPDATA\pnpm"
$env:PATH="$env:SystemDrive\postgrest;$postgreSQL;$env:NPM;$pnpm;$pnpm\bin;$env:LOCAL\bin;$env:PATH"

# $vsBuildTools="${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools"
#& "$vsBuildTools\Common7\Tools\VsDevCmd.bat"
#Import-Module "$vsBuildTools\Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
#Enter-VsDevShell -VsInstallPath $vsBuildTools -DevCmdArguments "-arch=x64 -host_arch=x64"
#$cl=(Get-ChildItem "$vsBuildTools\VC\Tools\MSVC\*\bin\Hostx64\x64" | Select-Object -Last 1).FullName

# init secrets
. $env:SCRIPTS\secrets.ps1

# source tools
Get-ChildItem "$env:DOTFILES\tools\*.ps1" | ForEach-Object { . $_.FullName }

# oh my posh
Invoke-Expression (oh-my-posh --init --shell pwsh --config "$env:DOTFILES\clean-detailed.omp.json")

# Activate vi mode
Set-PSReadLineOption -EditMode Vi

# Ctrl + y to accept suggestion
Set-PSReadLineKeyHandler -Key Ctrl+y -Function AcceptSuggestion

# Fix ls dir background color in output
$PSStyle.FileInfo.Directory = "`e[38;2;255;242;125m"

### Aliases ###
$CC="gcc"
$profile ="$env:DOTFILES\Microsoft.PowerShell_Profile.ps1"

function elevate { Start-Process powershell -Verb RunAs }
# function source { Remove-Variable * -Force -ErrorAction SilentlyContinue; . $profile }
function source { . $PROFILE }
function conf { cd $env:DOTFILES; v $env:DOTFILES }
function git-conf { cd $env:HOME; v $env:HOME\.gitconfig }
function notes { v $env:HOME\IdeaProjects\notes }
function profile { v $profile }
# Chrome with remote debugging on port 9222 in a separate profile: chrome-debug [url]
function chrome-debug {
    & "$env:ProgramFiles\Google\Chrome\Application\chrome.exe" `
        --remote-debugging-port=9222 `
        --user-data-dir="$env:LOCALAPPDATA\chrome-debug-profile" `
        --no-first-run `
        --no-default-browser-check `
        @args
}

# Abbreviations

Set-Alias p pnpm
Set-Alias which where
Set-Alias c clear
Set-Alias spot ncspot
# Set-Alias cl.exe "$cl\cl.exe"
# Set-Alias cl cl.exe
function ls { ls -la }
function .. { cd .. }
function ... { cd ..; cd .. }
function .... { cd ..; cd ..; cd .. }

## nvim

Set-Alias v nvim
function n { nvim . }

# Git aliases
function gcm { git checkout main }
function gL { git log }
function gs { git status }
function ga { git add . }
function gp { git push }
function gb { git branch }
function gcd { git checkout develop }
function gitlog { git log --oneline --graph --decorate }
Set-Alias gl gitlog -Force
