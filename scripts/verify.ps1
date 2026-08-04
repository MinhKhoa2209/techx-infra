$ErrorActionPreference = 'Stop'

foreach ($path in @('.gitignore', 'LICENSE', 'README.md')) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing required bootstrap file: $path"
  }
}

$forbidden = git ls-files | Select-String -Pattern '(^|/)(\.env$|\.terraform/)|\.(tfstate|tfplan)$|terraform\.tfvars$'
if ($forbidden) {
  throw "Forbidden generated or sensitive path is tracked: $($forbidden -join ', ')"
}

Write-Host 'techx-infra bootstrap verification passed.'

