# Windows configuration files

Use this at your own risk.

This repository contains configuration files and scripts for setting up and customizing a Windows environment. It includes settings for various applications, system tweaks, and automation scripts to streamline the setup process.

## Vscode (vim) settings and keybindings

Firstly, install the [Vscode Vim extension](https://marketplace.visualstudio.com/items?itemName=wy-z.vscode-vim-mode)

Then you could either copy parts of these config files or fork this repo and either set up symlinks for the "settings" and "keybindings" json files, or cloning it inside your Vscode User Directory. Symbolic links can be created with [mklink](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/mklink) on windows and [ln](https://linuxize.com/post/how-to-create-symbolic-links-in-linux-using-the-ln-command/) on linux.

## Setting up symbolic links

Choose either of the following commands to create symbolic links for configuration files:

- $sourcePath - Path to the original configuration file or directory.
- $targetPath - Path where the symbolic link should be created.

```powershell
# powershell
New-Item -ItemType SymbolicLink -Path $targetPath -Target $sourcePath -Force
```

```cmd
:: cmd
mklink $targetPath $sourcePath
```


## Resources

- [VscodeVim](https://github.com/VSCodeVim/Vim)
  - [Wiki](https://github.com/VSCodeVim/Vim/wiki)
- [Lukas W](https://gist.github.com/wojukasz)
