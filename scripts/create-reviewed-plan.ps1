param(
  [Parameter(Mandatory)][string]$BudgetAlertEmail,
  [Parameter(Mandatory)][datetimeoffset]$DestroyDeadline,
  [ValidateRange(1, 24)][int]$MaximumHours = 12,
  [ValidateSet('foundation', 'edge')][string]$Stage = 'foundation',
  [string]$PrivateVarFile = ''
)

$ErrorActionPreference = 'Stop'
$now = [datetimeoffset]::Now
if ($DestroyDeadline -le $now -or $DestroyDeadline -gt $now.AddHours(24)) {
  throw 'DestroyDeadline must be in the future and no more than 24 hours away.'
}

$root = Split-Path -Parent $PSScriptRoot
$demo = Join-Path $root 'environments/demo'
$planDirectory = Join-Path $root '.plans'
$planPath = Join-Path $planDirectory "demo-$Stage.tfplan"
$helmHome = Join-Path $root '.terraform-helm'
$privateVars = if ($PrivateVarFile) { $PrivateVarFile } else { Join-Path $demo 'domain-vpn.private.tfvars' }
if (-not (Test-Path -LiteralPath $privateVars)) {
  throw "Private variable file is required: $privateVars"
}
New-Item -ItemType Directory -Force -Path $planDirectory, (Join-Path $helmHome 'repository') | Out-Null

$preflight = & (Join-Path $PSScriptRoot 'preflight.ps1') -Stage $Stage | ConvertFrom-Json
$cost = & (Join-Path $PSScriptRoot 'cost-estimate.ps1') -Hours $MaximumHours -Profile domainVpn | ConvertFrom-Json
if ($cost.upperBoundUsd -gt 60) { throw 'Cost gate failed.' }

$env:HELM_REPOSITORY_CONFIG = Join-Path $helmHome 'repositories.yaml'
$env:HELM_REPOSITORY_CACHE = Join-Path $helmHome 'repository'
$env:TF_VAR_public_access_cidrs = ConvertTo-Json @($preflight.callerPublicCidr) -Compress
$env:TF_VAR_budget_alert_email = $BudgetAlertEmail

try {
  helm repo add eks https://aws.github.io/eks-charts --force-update | Out-Null
  helm repo add argo https://argoproj.github.io/argo-helm --force-update | Out-Null
  helm repo update eks argo | Out-Null

  terraform "-chdir=$demo" init -backend=false | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'terraform init failed.' }
  $planArgs = @(
    '-input=false', '-refresh=false', '-no-color', "-out=$planPath",
    "-var-file=$privateVars",
    '-var=enable_domain_vpn_foundation=true',
    "-var=enable_domain_vpn_edge=$($Stage -eq 'edge' ? 'true' : 'false')"
  )
  terraform "-chdir=$demo" plan @planArgs | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'terraform plan failed.' }

  $review = terraform "-chdir=$demo" show -json $planPath | python (Join-Path $PSScriptRoot 'review-plan.py') $Stage | ConvertFrom-Json
  if ($LASTEXITCODE -ne 0) { throw 'Saved-plan review failed.' }
  $hash = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant()

  $summary = @"
STATUS: WAITING_FOR_USER_APPROVAL
Stage: $Stage
Account ID: $($preflight.accountId)
Caller: $($preflight.callerArn)
Region: $($preflight.region)
EKS API CIDR: $($preflight.callerPublicCidr)
Saved plan: .plans/demo-$Stage.tfplan
SHA256: $hash
Resources: $($review.resourceCount) add, 0 change, 0 destroy
Estimated upper bound: $($cost.upperBoundUsd) USD for <= $MaximumHours hours
Apply gate: 60 USD; hard cap: 80 USD
Budget alerts in plan: 40, 60, 72 USD
Destroy deadline: $($DestroyDeadline.ToString('yyyy-MM-dd HH:mm:ss zzz'))

Required confirmation (do not run yet):
Tôi xác nhận apply AWS plan này, ngân sách tối đa 80 USD và destroy trước $($DestroyDeadline.ToString('yyyy-MM-dd HH:mm:ss zzz')).
"@
  $summary | Set-Content -LiteralPath (Join-Path $root "approval-summary-$Stage.private.txt") -Encoding utf8
  $preflight | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $root 'preflight.private.json') -Encoding utf8
  Write-Output $summary
}
finally {
  Remove-Item Env:TF_VAR_public_access_cidrs, Env:TF_VAR_budget_alert_email, Env:HELM_REPOSITORY_CONFIG, Env:HELM_REPOSITORY_CACHE -ErrorAction SilentlyContinue
}
