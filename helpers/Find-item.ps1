param(
  [Parameter(Mandatory = $true)]
  [string]$Name,
  [string]$Path = ".",
  [switch]$Recurse = $true
)

$searchParams = @{
  Path = $Path
  Filter = "*$Name*"
  ErrorAction = "SilentlyContinue"
}

Write-Host "Searching for items matching '$Name' in '$Path'..." -ForegroundColor Cyan
$files = Get-ChildItem @searchParams -File
$folders = Get-ChildItem @searchParams -Directory

Write-Host "`nFiles found:" -ForegroundColor Yellow
$files | Select-Object FullName

Write-Host "`nFolders found:" -ForegroundColor Yellow
$folders | Select-Object FullName
