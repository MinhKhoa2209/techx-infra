$ErrorActionPreference = 'Stop'

foreach ($path in @('.gitignore', 'LICENSE', 'README.md', 'scripts/apply-reviewed-plan.ps1')) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing required bootstrap file: $path"
  }
}

$demo = Join-Path (Split-Path -Parent $PSScriptRoot) 'environments/demo'
terraform "-chdir=$demo" fmt -check -recursive
if ($LASTEXITCODE -ne 0) { throw 'terraform fmt -check failed.' }
terraform "-chdir=$demo" init -backend=false
if ($LASTEXITCODE -ne 0) { throw 'terraform init failed.' }
terraform "-chdir=$demo" validate
if ($LASTEXITCODE -ne 0) { throw 'terraform validate failed.' }
python (Join-Path $PSScriptRoot 'static-test.py')
if ($LASTEXITCODE -ne 0) { throw 'Terraform static assertions failed.' }
& (Join-Path $PSScriptRoot 'cost-estimate.ps1') -Hours 12 | Out-Null
& (Join-Path $PSScriptRoot 'security-scan.ps1')

$forbidden = git ls-files | Select-String -Pattern '(^|/)(\.env$|\.terraform/)|\.(tfstate|tfplan)$|terraform\.tfvars$'
if ($forbidden) {
  throw "Forbidden generated or sensitive path is tracked: $($forbidden -join ', ')"
}

Write-Host 'techx-infra offline verification passed.'
