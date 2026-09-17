$errs = $null
$target = Join-Path (Split-Path -Parent $PSScriptRoot) 'pet.ps1'
$null = [System.Management.Automation.Language.Parser]::ParseFile($target, [ref]$null, [ref]$errs)
if ($errs -and $errs.Count -gt 0) {
  $errs | ForEach-Object { Write-Host ("ERR line {0}: {1}" -f $_.Extent.StartLineNumber, $_.Message) }
  exit 1
} else {
  Write-Host 'SYNTAX-OK'
}
