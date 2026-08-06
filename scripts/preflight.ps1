param([string]$Region = 'us-east-1', [string]$KubernetesVersion = '1.35')

$ErrorActionPreference = 'Stop'
$identity = aws sts get-caller-identity --output json | ConvertFrom-Json
if (-not $identity.Account) { throw 'Unable to resolve AWS caller identity.' }
$ip = (Invoke-RestMethod -Uri 'https://checkip.amazonaws.com').Trim()
if ($ip -notmatch '^([0-9]{1,3}\.){3}[0-9]{1,3}$') { throw 'Unable to resolve caller public IPv4.' }

$versions = aws eks describe-cluster-versions --region $Region --no-include-all --output json | ConvertFrom-Json
$selected = $versions.clusterVersions | Where-Object { $_.clusterVersion -eq $KubernetesVersion -and $_.status -eq 'STANDARD_SUPPORT' }
if (-not $selected) { throw "EKS $KubernetesVersion is not in standard support in $Region." }
$zones = aws ec2 describe-availability-zones --region $Region --filters Name=state,Values=available --output json | ConvertFrom-Json
if ($zones.AvailabilityZones.Count -lt 2) { throw 'Fewer than two available AZs were returned.' }
$offerings = aws ec2 describe-instance-type-offerings --region $Region --location-type availability-zone --filters Name=instance-type,Values=t3.medium --output json | ConvertFrom-Json
if ($offerings.InstanceTypeOfferings.Count -lt 2) { throw 't3.medium is unavailable in at least two AZs.' }

$clusterQuota = aws service-quotas get-service-quota --service-code eks --quota-code L-1194D53C --region $Region --output json | ConvertFrom-Json
$vcpuQuota = aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A --region $Region --output json | ConvertFrom-Json
if ($clusterQuota.Quota.Value -lt 1 -or $vcpuQuota.Quota.Value -lt 2) { throw 'Required EKS or EC2 quota is unavailable.' }

$addons = @{}
foreach ($addon in @('vpc-cni', 'kube-proxy', 'coredns')) {
  $response = aws eks describe-addon-versions --region $Region --kubernetes-version $KubernetesVersion --addon-name $addon --output json | ConvertFrom-Json
  $default = $response.addons[0].addonVersions | Where-Object { $_.compatibilities[0].defaultVersion } | Select-Object -First 1
  if (-not $default.addonVersion) { throw "No compatible default version found for $addon." }
  $addons[$addon] = $default.addonVersion
}
$budgets = aws budgets describe-budgets --account-id $identity.Account --output json | ConvertFrom-Json

$conflicts = @()
$clusters = @(aws eks list-clusters --region $Region --query 'clusters' --output json | ConvertFrom-Json)
if ($clusters -contains 'techx-demo') { $conflicts += 'EKS cluster techx-demo' }
$repositories = @(aws ecr describe-repositories --region $Region --query 'repositories[].repositoryName' --output json | ConvertFrom-Json)
foreach ($name in @('techx/frontend', 'techx/catalog', 'techx/order')) {
  if ($repositories -contains $name) { $conflicts += "ECR repository $name" }
}
$roles = @(aws iam list-roles --query 'Roles[].RoleName' --output json | ConvertFrom-Json)
foreach ($name in @('techx-demo-cluster', 'techx-demo-node', 'techx-demo-aws-load-balancer-controller')) {
  if ($roles -contains $name) { $conflicts += "IAM role $name" }
}
$logGroups = @(aws logs describe-log-groups --region $Region --log-group-name-prefix '/aws/eks/techx-demo/cluster' --query 'logGroups[].logGroupName' --output json | ConvertFrom-Json)
if ($logGroups -contains '/aws/eks/techx-demo/cluster') { $conflicts += 'CloudWatch log group /aws/eks/techx-demo/cluster' }
if (@($budgets.Budgets.BudgetName) -contains 'techx-demo-hard-cap') { $conflicts += 'AWS Budget techx-demo-hard-cap' }
if ($conflicts.Count -gt 0) { throw "Pre-existing resource name conflicts found: $($conflicts -join ', ')" }

$requiredActions = @('eks:CreateCluster', 'eks:DeleteCluster', 'ec2:CreateVpc', 'ec2:RunInstances', 'iam:CreateRole', 'iam:CreatePolicy', 'ecr:CreateRepository', 'budgets:ModifyBudget', 'elasticloadbalancing:CreateLoadBalancer')
$simulation = aws iam simulate-principal-policy --policy-source-arn $identity.Arn --action-names $requiredActions --output json | ConvertFrom-Json
$denied = @($simulation.EvaluationResults | Where-Object { $_.EvalDecision -ne 'allowed' })
if ($denied.Count -gt 0) { throw "Permission simulation did not allow: $($denied.EvalActionName -join ', ')" }

[pscustomobject]@{
  accountId = $identity.Account; callerArn = $identity.Arn; region = $Region
  callerPublicCidr = "$ip/32"; kubernetesVersion = $selected.clusterVersion
  kubernetesStatus = $selected.status; standardSupportEnds = $selected.endOfStandardSupportDate
  availableZones = @($zones.AvailabilityZones.ZoneName); t3MediumZones = @($offerings.InstanceTypeOfferings.Location)
  eksClusterQuota = $clusterQuota.Quota.Value; standardOnDemandVcpuQuota = $vcpuQuota.Quota.Value
  compatibleDefaultAddonVersion = $addons
  existingBudgets = @($budgets.Budgets | ForEach-Object { @{ name = $_.BudgetName; amount = $_.BudgetLimit.Amount; unit = $_.BudgetLimit.Unit } })
  permissionSimulation = @($simulation.EvaluationResults | ForEach-Object { @{ action = $_.EvalActionName; decision = $_.EvalDecision } })
  resourceNameConflicts = $conflicts
} | ConvertTo-Json -Depth 6
