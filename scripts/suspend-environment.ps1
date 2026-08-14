param(
  [string]$Region = 'us-east-1',
  [string]$ClusterName = 'techx-demo',
  [string]$NodeGroupName = 'demo',
  [string]$Application = 'techx-demo',
  [Parameter(Mandatory)][datetimeoffset]$RetentionDeadline,
  [ValidateRange(60, 1800)][int]$TimeoutSeconds = 900
)

$ErrorActionPreference = 'Stop'
if ($RetentionDeadline -le [datetimeoffset]::Now -or $RetentionDeadline -gt [datetimeoffset]::Now.AddDays(7)) {
  throw 'RetentionDeadline must be in the future and no more than seven days away.'
}

aws eks describe-cluster --region $Region --name $ClusterName --output json | Out-Null
if ($LASTEXITCODE -ne 0) { throw "EKS cluster $ClusterName is unavailable." }
aws eks update-kubeconfig --region $Region --name $ClusterName | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Unable to configure kubectl.' }

$applicationExists = kubectl -n argocd get application $Application --ignore-not-found -o name
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the Argo CD Application.' }
if ($applicationExists) {
  kubectl -n argocd delete application $Application --cascade=foreground --wait=true --timeout="${TimeoutSeconds}s"
  if ($LASTEXITCODE -ne 0) { throw 'Argo CD Application removal failed.' }
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
do {
  $ingress = kubectl -n techx-demo get ingress --ignore-not-found -o name
  if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect workload Ingress resources.' }
  $loadBalancers = aws elbv2 describe-load-balancers --region $Region --query "LoadBalancers[?contains(LoadBalancerName, 'techx')].LoadBalancerArn" --output json | ConvertFrom-Json
  if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect AWS load balancers.' }
  if (-not $ingress -and @($loadBalancers).Count -eq 0) { break }
  Start-Sleep -Seconds 10
} while ((Get-Date) -lt $deadline)
if ($ingress -or @($loadBalancers).Count -gt 0) { throw 'Ingress or TechX load balancer still exists; worker scale-down was not attempted.' }

aws eks update-nodegroup-config --region $Region --cluster-name $ClusterName --nodegroup-name $NodeGroupName --scaling-config minSize=0,maxSize=1,desiredSize=0 --output json | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Node group scale-down request failed.' }
aws eks wait nodegroup-active --region $Region --cluster-name $ClusterName --nodegroup-name $NodeGroupName
if ($LASTEXITCODE -ne 0) { throw 'Node group did not return to ACTIVE after scale-down.' }

$state = [ordered]@{
  state = 'IDLE'
  region = $Region
  clusterName = $ClusterName
  nodeGroupName = $NodeGroupName
  suspendedAt = [datetimeoffset]::Now.ToString('o')
  retentionDeadline = $RetentionDeadline.ToString('o')
}
$state | ConvertTo-Json | Set-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'environment-state.private.json') -Encoding utf8
$state | ConvertTo-Json
