# compact-disks: return space freed inside WSL and Docker Desktop to C:.
#
# Space freed inside a WSL distro or Docker Desktop stays in its .vhdx until
# the disk is compacted. This trims every WSL distro, shuts down WSL and Docker
# Desktop, compacts each distro disk and Docker's data disk with diskpart, and
# marks the distro disks sparse so later frees return to C: by themselves.
# Disks are found from the WSL registry, so nothing is machine-specific.
# Safe to re-run. Everything running in WSL or Docker stops.
#
# Apps that read WSL paths (Claude Code or Codex sessions whose skills or
# config link into a distro, Explorer windows on \\wsl.localhost, IDEs) start
# WSL again right after the shutdown; the script waits until they are closed.
#
# Usage: close those apps, then run `compact-disks` in an admin PowerShell.
function compact-disks {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { Write-Host 'compact-disks needs an admin PowerShell.' -ForegroundColor Yellow; return }

    $ErrorActionPreference = 'Stop'
    $freeGB = { [math]::Round((Get-PSDrive C).Free / 1GB, 1) }
    $sizeGB = { param($path) [math]::Round((Get-Item $path).Length / 1GB, 1) }

    # Distro disks from the WSL registry; docker-desktop's own small disk is skipped.
    $distros = @(Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' |
        ForEach-Object { Get-ItemProperty $_.PSPath } |
        Where-Object { $_.DistributionName -ne 'docker-desktop' } |
        ForEach-Object {
            [pscustomobject]@{ Name = $_.DistributionName; Vhdx = Join-Path $_.BasePath 'ext4.vhdx' }
        } |
        Where-Object { Test-Path $_.Vhdx })

    $disks = @($distros | ForEach-Object { $_.Vhdx })
    $dockerVhdx = "$env:LOCALAPPDATA\Docker\wsl\disk\docker_data.vhdx"
    if (Test-Path $dockerVhdx) { $disks += $dockerVhdx }

    $before = & $freeGB
    Write-Host "C: free now: $before GB"
    foreach ($d in $disks) { Write-Host ("  {0,7} GB  {1}" -f (& $sizeGB $d), $d) }
    Write-Host 'This shuts down WSL and Docker Desktop. Everything running in them stops.'
    if ((Read-Host 'Continue? [y/N]') -ne 'y') { Write-Host 'Nothing changed.'; return }

    # 1. Tell each filesystem which blocks are free, so compaction can drop them.
    foreach ($d in $distros) {
        Write-Host "Trimming $($d.Name)..."
        wsl.exe -d $d.Name -u root -- fstrim -av
    }

    # Shut WSL down and make sure it stays down. Any app that reads a WSL path
    # (\\wsl.localhost\..., e.g. a Claude Code or Codex session whose skills
    # or config link into a distro, Explorer, an IDE) starts the distro again
    # within seconds, and a running distro's disk can't be compacted.
    $env:WSL_UTF8 = '1'
    $stopWsl = {
        while ($true) {
            wsl.exe --shutdown
            $running = @()
            foreach ($i in 1..5) {
                Start-Sleep -Seconds 2
                $running = @(wsl.exe --list --running --quiet 2>$null |
                    Where-Object { $_.Trim() -and $_ -notmatch 'no running' })
                if ($running.Count) { break }
            }
            if (-not $running.Count) { return $true }
            Write-Host "WSL restarted by itself: $($running -join ', ') is running again." -ForegroundColor Yellow
            $users = Get-Process claude, codex, Code, idea64, explorer -ErrorAction SilentlyContinue |
                Group-Object Name | ForEach-Object { "$($_.Name) ($($_.Count))" }
            Write-Host "Close what reads WSL files, then retry. Running now: $($users -join ', ')"
            if ((Read-Host 'Retry? [Y/n]') -eq 'n') { return $false }
        }
    }

    # 2. Stop Docker Desktop and WSL.
    Write-Host 'Stopping Docker Desktop and WSL...'
    Get-Process 'Docker Desktop', 'com.docker.backend', 'com.docker.build' -ErrorAction SilentlyContinue |
        Stop-Process -Force

    # 3. Compact each disk with diskpart (works without the Hyper-V module).
    foreach ($vhdx in $disks) {
        if (-not (& $stopWsl)) { Write-Host "Skipped $vhdx"; continue }
        $sizeBefore = & $sizeGB $vhdx
        Write-Host "Compacting $vhdx ($sizeBefore GB)..."
        $dp = Join-Path $env:TEMP 'compact-disks.diskpart'
        @("select vdisk file=`"$vhdx`"", 'attach vdisk readonly', 'compact vdisk', 'detach vdisk') |
            Set-Content -Path $dp -Encoding ascii
        diskpart.exe /s $dp | Out-Host
        $ok = $LASTEXITCODE -eq 0
        Remove-Item $dp -Force
        if ($ok) { Write-Host "  $sizeBefore GB -> $(& $sizeGB $vhdx) GB" }
        else { Write-Host "  diskpart failed (exit $LASTEXITCODE); $vhdx is unchanged" -ForegroundColor Red }
    }

    # 4. Make the distro disks sparse so future frees return to C: automatically.
    foreach ($d in $distros) {
        if ((Get-Item $d.Vhdx).Attributes -band [IO.FileAttributes]::SparseFile) {
            Write-Host "$($d.Name) is already sparse"; continue
        }
        if (-not (& $stopWsl)) { Write-Host "Skipped marking $($d.Name) sparse"; continue }
        Write-Host "Marking $($d.Name) sparse..."
        wsl.exe --manage $d.Name --set-sparse true
        if ($LASTEXITCODE -ne 0) { Write-Host "  failed for $($d.Name)" -ForegroundColor Red }
    }

    Write-Host "C: free: $before GB -> $(& $freeGB) GB"
    Write-Host 'Start Docker Desktop again when you need it; WSL starts on first use.'
}
