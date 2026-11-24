@echo off
:: Creates symbolic links for dotfiles from %USERPROFILE%\dotfiles to %USERPROFILE%
:: Removes existing files/links before creating new ones
setlocal enabledelayedexpansion

set files[0]=.wezterm.lua
set files[1]=.ripgreprc
set files[2]=.ideavimrc
set files[3]=.vscode/settings.json
set files[4]=.vscode/keybindings.json
set files[5]=.vscode/mcp.json
set files[6]=nvim/init.lua
set files[7]=Microsoft.PowerShell_profile.ps1

set targets[3]=AppData\Roaming\Code\User\settings.json
set targets[4]=AppData\Roaming\Code\User\keybindings.json
set targets[5]=AppData\Roaming\Code\User\mcp.json
set targets[6]=AppData\Local\nvim\init.lua
set targets[7]=Documents\Powershell\Microsoft.Powershell_profile.ps1

for /L %%i in (0,1,6) do (
    call set "file=%%files[%%i]%%"
    call set "target_path=%%targets[%%i]%%"
    if "!target_path!"=="" set "target_path=!file!"
    set "target=%USERPROFILE%\!target_path!"
    set "source=%USERPROFILE%\dotfiles\!file!"
    if exist "!target!" del "!target!"
    mklink "!target!" "!source!"
)
