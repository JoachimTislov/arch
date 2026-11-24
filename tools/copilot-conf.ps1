#--agent frontend `
function copilot {
 . "$env:NPM\copilot.ps1" `
    --model gpt-5.1-codex-mini `
    --allow-tool 'Figma-desktop' `
    --allow-tool 'write' `
    --allow-tool 'svelte' `
    --allow-tool 'mui' `
    --deny-tool 'shell(rm -r)' `
    --allow-tool 'shell(git:*)' `
    --deny-tool 'shell(git checkout)' `
    --deny-tool 'shell(git reset)' `
    --deny-tool 'shell(git push)' `
    --deny-tool 'shell(git branch)' `
    --deny-tool 'shell(git rebase)' `
    --deny-tool 'shell(git merge)' `
    --deny-tool 'shell(git clean -fd)' `
    --deny-tool 'shell(git reflog expire)' `
    --deny-tool 'shell(git gc --prune)' `
    @args
}
