param(
  [Parameter(Mandatory)][ValidatePattern('^[0-9]{12}$')][string]$ExpectedAccountId,
  [Parameter(Mandatory)][switch]$ConfirmDestroy,
  [string]$Region = 'us-east-1',
  [string]$PrivateVarFile = '',
  [ValidateRange(300, 3600)][int]$TimeoutSeconds = 1800
)

$ErrorActionPreference = 'Stop'
if (-not $ConfirmDestroy) { throw 'ConfirmDestroy is required.' }

$root = Split-Path -Parent $PSScriptRoot
$demo = Join-Path $root 'environments/demo'
$privateVars = if ($PrivateVarFile) { $PrivateVarFile } else { Join-Path $demo 'domain-vpn.private.tfvars' }
$helmHome = Join-Path $root '.terraform-helm'
if (-not (Test-Path -LiteralPath $privateVars)) { throw "Private variable file is missing: $privateVars" }

$identity = aws sts get-caller-identity --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $identity.Account -ne $ExpectedAccountId) {
  throw 'Current AWS identity does not match ExpectedAccountId.'
}

$publicDns = @(Resolve-DnsName -Name 'shop.dinhminhkhoa.id.vn' -Type CNAME -ErrorAction SilentlyContinue)
if (@($publicDns | Where-Object { $_.NameHost -like '*.cloudfront.net' }).Count -gt 0) {
  throw 'Remove the Cloudflare shop CNAME first to avoid dangling DNS, then rerun teardown.'
}

New-Item -ItemType Directory -Force -Path (Join-Path $helmHome 'repository') | Out-Null
$env:HELM_REPOSITORY_CONFIG = Join-Path $helmHome 'repositories.yaml'
$env:HELM_REPOSITORY_CACHE = Join-Path $helmHome 'repository'

try {
  helm repo add eks https://aws.github.io/eks-charts --force-update | Out-Null
  helm repo add argo https://argoproj.github.io/argo-helm --force-update | Out-Null
  helm repo update eks argo | Out-Null
  terraform "-chdir=$demo" init -backend=false | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'terraform init failed.' }

  # Edge resources are removed first while their internal ALB origin still exists.
  terraform "-chdir=$demo" apply -auto-approve -input=false -no-color `
    "-var-file=$privateVars" `
    '-var=enable_domain_vpn_foundation=true' `
    '-var=enable_domain_vpn_edge=false'
  if ($LASTEXITCODE -ne 0) { throw 'Unable to remove CloudFront, private DNS, and Client VPN resources.' }

  aws eks update-kubeconfig --region $Region --name techx-demo | Out-Null
  if ($LASTEXITCODE -eq 0) {
    kubectl -n argocd delete application techx-demo --cascade=foreground --ignore-not-found --wait=true --timeout="${TimeoutSeconds}s"
    if ($LASTEXITCODE -ne 0) { throw 'Unable to remove the workload Application.' }
    kubectl -n argocd delete ingress --all --ignore-not-found --wait=true --timeout="${TimeoutSeconds}s"
    if ($LASTEXITCODE -ne 0) { throw 'Unable to remove the Argo CD Ingress.' }
  }

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    $loadBalancers = @(aws resourcegroupstaggingapi get-resources --region $Region `
        --tag-filters Key=Project,Values=techx `
        --resource-type-filters elasticloadbalancing:loadbalancer `
        --query 'ResourceTagMappingList[].ResourceARN' --output json | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inventory TechX load balancers.' }
    if ($loadBalancers.Count -eq 0) { break }
    Start-Sleep -Seconds 10
  } while ((Get-Date) -lt $deadline)
  if ($loadBalancers.Count -gt 0) { throw 'A TechX ALB still exists; foundation destroy was not started.' }

  terraform "-chdir=$demo" destroy -auto-approve -input=false -no-color `
    "-var-file=$privateVars" `
    '-var=enable_domain_vpn_foundation=true' `
    '-var=enable_domain_vpn_edge=false'
  if ($LASTEXITCODE -ne 0) { throw 'Foundation destroy failed.' }

  $certificateStatePath = Join-Path $root 'certificate-state.private.json'
  $certificateArns = @()
  if (Test-Path -LiteralPath $certificateStatePath) {
    $certificateState = Get-Content -LiteralPath $certificateStatePath -Raw | ConvertFrom-Json
    $certificateArns += @(
      $certificateState.publicCertificateArn,
      $certificateState.clientVpnServerCertificateArn,
      $certificateState.clientVpnRootCertificateArn
    ) | Where-Object { $_ }
  }
  $publicCertificates = aws acm list-certificates --region $Region --output json | ConvertFrom-Json
  if ($LASTEXITCODE -ne 0) { throw 'Unable to inventory ACM certificates.' }
  foreach ($certificate in @($publicCertificates.CertificateSummaryList | Where-Object { $_.DomainName -eq 'shop.dinhminhkhoa.id.vn' })) {
    $certificateTags = aws acm list-tags-for-certificate --region $Region --certificate-arn $certificate.CertificateArn --output json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect ACM certificate tags for $($certificate.CertificateArn)." }
    if (@($certificateTags.Tags | Where-Object { $_.Key -eq 'Project' -and $_.Value -eq 'techx' }).Count -eq 1) {
      $certificateArns += $certificate.CertificateArn
    }
  }
  foreach ($certificateArn in @($certificateArns | Sort-Object -Unique)) {
    if ($certificateArn -notmatch "^arn:aws:acm:${Region}:$ExpectedAccountId:certificate/") {
      throw "Refusing to delete an ACM certificate outside the approved account/region: $certificateArn"
    }
    $certificateTags = aws acm list-tags-for-certificate --region $Region --certificate-arn $certificateArn --output json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or @($certificateTags.Tags | Where-Object { $_.Key -eq 'Project' -and $_.Value -eq 'techx' }).Count -ne 1) {
      throw "Refusing to delete untagged ACM certificate $certificateArn."
    }
    aws acm delete-certificate --region $Region --certificate-arn $certificateArn
    if ($LASTEXITCODE -ne 0) { throw "Unable to delete ACM certificate $certificateArn." }
  }
  if (Test-Path -LiteralPath $certificateStatePath) { [IO.File]::Delete($certificateStatePath) }

  $inventory = & (Join-Path $PSScriptRoot 'domain-vpn-inventory.ps1') -Region $Region | ConvertFrom-Json
  if ($inventory.clusters.Count -gt 0 -or $inventory.loadBalancerArns.Count -gt 0 -or
      $inventory.clientVpn.Count -gt 0 -or $inventory.cloudFront.Count -gt 0 -or
      $inventory.privateHostedZones.Count -gt 0 -or $inventory.ecrRepositories.Count -gt 0 -or
      $inventory.acmCertificates.Count -gt 0) {
    throw "Final inventory is not empty: $($inventory | ConvertTo-Json -Depth 8 -Compress)"
  }
  $inventory | ConvertTo-Json -Depth 8
}
finally {
  Remove-Item Env:HELM_REPOSITORY_CONFIG, Env:HELM_REPOSITORY_CACHE -ErrorAction SilentlyContinue
}
