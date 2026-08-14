param(
  [string]$Region = 'us-east-1',
  [string]$ClusterName = 'techx-demo',
  [string]$NodeGroupName = 'demo',
  [ValidateRange(120, 1800)][int]$TimeoutSeconds = 900
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$statePath = Join-Path $root 'environment-state.private.json'
if (-not (Test-Path -LiteralPath $statePath)) { throw 'The private environment state file is missing.' }
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
if ($state.state -ne 'IDLE') { throw 'The environment is not recorded as IDLE.' }
if ([datetimeoffset]::Parse($state.retentionDeadline) -le [datetimeoffset]::Now) { throw 'The retention deadline has expired; do not resume before reviewing cost and teardown.' }

aws eks update-nodegroup-config --region $Region --cluster-name $ClusterName --nodegroup-name $NodeGroupName --scaling-config minSize=0,maxSize=1,desiredSize=1 --output json | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Node group scale-up request failed.' }
aws eks wait nodegroup-active --region $Region --cluster-name $ClusterName --nodegroup-name $NodeGroupName
if ($LASTEXITCODE -ne 0) { throw 'Node group did not return to ACTIVE after scale-up.' }
aws eks update-kubeconfig --region $Region --name $ClusterName | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Unable to configure kubectl.' }
kubectl wait --for=condition=Ready nodes --all --timeout="${TimeoutSeconds}s"
if ($LASTEXITCODE -ne 0) { throw 'The worker node did not become Ready.' }

$secret = kubectl -n techx-demo get secret techx-demo-secrets --ignore-not-found -o name
if ($LASTEXITCODE -ne 0 -or -not $secret) { throw 'Required Secret techx-demo-secrets is missing; restore it before applying the Argo CD Application.' }
$applicationPath = Join-Path (Split-Path -Parent $root) 'techx-chart/gitops/clusters/demo/application.yaml'
kubectl apply -f $applicationPath | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Unable to apply the Argo CD Application.' }

$state.state = 'ACTIVE'
$state | Add-Member -NotePropertyName resumedAt -NotePropertyValue ([datetimeoffset]::Now.ToString('o')) -Force
$state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding utf8
$state | ConvertTo-Json
