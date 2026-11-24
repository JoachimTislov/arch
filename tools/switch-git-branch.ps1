function sb {
    # Get all branches and pipe to fzf for selection
    $branchName = git branch --all | ForEach-Object { $_.Trim() -replace '^\*?\s*', '' -replace '^remotes/origin/', '' } | Sort-Object -Unique | Where-Object { $_ -ne 'HEAD' } | fzf

    if (-not $branchName) {
        Write-Host "No branch selected." -ForegroundColor Yellow
        return
    }

    Write-Host "Switching to branch '$branchName'..." -ForegroundColor Cyan

    git checkout $branchName 2>&1
}

# Usage: Select a branch from the list of all branches (local and remote) and switch to it.
