$ErrorActionPreference = 'Stop'

foreach ($path in @(
    '.gitignore', 'LICENSE', 'README.md',
    'scripts/apply-reviewed-plan.ps1',
    'scripts/create-reviewed-plan.ps1',
    'scripts/domain-vpn-inventory.ps1',
    'scripts/destroy-domain-vpn-environment.ps1',
    'scripts/new-client-vpn-pki.ps1',
    'scripts/prepare-domain-certificates.ps1',
    'scripts/export-client-vpn-profile.ps1'
  )) {
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

foreach ($script in @(
    'apply-reviewed-plan.ps1', 'create-reviewed-plan.ps1', 'preflight.ps1',
    'domain-vpn-inventory.ps1', 'destroy-domain-vpn-environment.ps1',
    'new-client-vpn-pki.ps1', 'prepare-domain-certificates.ps1',
    'export-client-vpn-profile.ps1', 'suspend-environment.ps1',
    'resume-environment.ps1'
  )) {
  $tokens = $null
  $parseErrors = $null
  [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot $script), [ref]$tokens, [ref]$parseErrors
  ) | Out-Null
  if ($parseErrors) { throw "$script has syntax errors: $($parseErrors.Message -join '; ')" }
}

$forbidden = git ls-files | Select-String -Pattern '(^|/)(\.env$|\.terraform/)|\.(tfstate|tfplan|ovpn|key|crt|pem|p12|pfx)$|terraform\.tfvars$|\.private\.tfvars$'
if ($forbidden) {
  throw "Forbidden generated or sensitive path is tracked: $($forbidden -join ', ')"
}

Write-Host 'techx-infra offline verification passed.'
