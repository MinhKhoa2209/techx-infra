param(
  [string]$Region = 'us-east-1',
  [string]$DomainName = 'shop.dinhminhkhoa.id.vn'
)

$ErrorActionPreference = 'Stop'

function Invoke-AwsJson([string[]]$Arguments) {
  $raw = & aws @Arguments --output json
  if ($LASTEXITCODE -ne 0) { throw "aws failed: $($Arguments -join ' ')" }
  return $raw | ConvertFrom-Json
}

$identity = Invoke-AwsJson @('sts', 'get-caller-identity')
$clusters = @(@(Invoke-AwsJson @('eks', 'list-clusters', '--region', $Region)).clusters |
    Where-Object { $_ -eq 'techx-demo' })

$nodeGroups = @()
foreach ($cluster in $clusters) {
  $names = @(Invoke-AwsJson @('eks', 'list-nodegroups', '--region', $Region, '--cluster-name', $cluster)).nodegroups
  foreach ($name in $names) {
    $node = (Invoke-AwsJson @('eks', 'describe-nodegroup', '--region', $Region, '--cluster-name', $cluster, '--nodegroup-name', $name)).nodegroup
    $nodeGroups += [ordered]@{
      cluster = $cluster
      name = $name
      status = $node.status
      desired = $node.scalingConfig.desiredSize
      minimum = $node.scalingConfig.minSize
      maximum = $node.scalingConfig.maxSize
    }
  }
}

$taggedLoadBalancers = Invoke-AwsJson @(
  'resourcegroupstaggingapi', 'get-resources', '--region', $Region,
  '--tag-filters', 'Key=Project,Values=techx',
  '--resource-type-filters', 'elasticloadbalancing:loadbalancer'
)
$loadBalancers = @($taggedLoadBalancers.ResourceTagMappingList | ForEach-Object { $_.ResourceARN } | Where-Object { $_ })

$vpnEndpoints = @((Invoke-AwsJson @(
      'ec2', 'describe-client-vpn-endpoints', '--region', $Region,
      '--filters', 'Name=tag:Project,Values=techx'
    )).ClientVpnEndpoints)
$vpn = @()
foreach ($endpoint in $vpnEndpoints) {
  $associations = @((Invoke-AwsJson @(
        'ec2', 'describe-client-vpn-target-networks', '--region', $Region,
        '--client-vpn-endpoint-id', $endpoint.ClientVpnEndpointId
      )).ClientVpnTargetNetworks)
  $connections = @((Invoke-AwsJson @(
        'ec2', 'describe-client-vpn-connections', '--region', $Region,
        '--client-vpn-endpoint-id', $endpoint.ClientVpnEndpointId
      )).Connections | Where-Object { $_.Status.Code -eq 'active' })
  $vpn += [ordered]@{
    id = $endpoint.ClientVpnEndpointId
    status = $endpoint.Status.Code
    associations = @($associations | ForEach-Object { @{ id = $_.AssociationId; status = $_.Status.Code; subnetId = $_.TargetNetworkId } })
    activeConnections = $connections.Count
  }
}

$distributionList = Invoke-AwsJson @('cloudfront', 'list-distributions')
$distributions = @($distributionList.DistributionList.Items | Where-Object { $_.Aliases.Items -contains $DomainName } | ForEach-Object {
    @{ id = $_.Id; domainName = $_.DomainName; status = $_.Status; enabled = $_.Enabled }
  })
$zones = @((Invoke-AwsJson @('route53', 'list-hosted-zones-by-name', '--dns-name', $DomainName)).HostedZones |
    Where-Object { $_.Name.TrimEnd('.') -eq $DomainName -and $_.Config.PrivateZone })
$repositories = @((Invoke-AwsJson @('ecr', 'describe-repositories', '--region', $Region)).repositories |
    Where-Object { $_.repositoryName -in @('techx/frontend', 'techx/catalog', 'techx/order') } |
    ForEach-Object { $_.repositoryName })
$certificateTags = Invoke-AwsJson @(
  'resourcegroupstaggingapi', 'get-resources', '--region', $Region,
  '--tag-filters', 'Key=Project,Values=techx',
  '--resource-type-filters', 'acm:certificate'
)
$certificates = @()
foreach ($mapping in @($certificateTags.ResourceTagMappingList)) {
  $certificate = (Invoke-AwsJson @('acm', 'describe-certificate', '--region', $Region, '--certificate-arn', $mapping.ResourceARN)).Certificate
  $role = @($mapping.Tags | Where-Object { $_.Key -eq 'Role' } | Select-Object -First 1).Value
  $certificates += @{ arn = $mapping.ResourceARN; domainName = $certificate.DomainName; status = $certificate.Status; role = $role }
}

[ordered]@{
  checkedAt = [datetimeoffset]::Now.ToString('o')
  accountId = $identity.Account
  region = $Region
  clusters = $clusters
  nodeGroups = $nodeGroups
  loadBalancerArns = $loadBalancers
  clientVpn = $vpn
  cloudFront = $distributions
  privateHostedZones = @($zones | ForEach-Object { @{ id = $_.Id; name = $_.Name } })
  ecrRepositories = $repositories
  acmCertificates = $certificates
} | ConvertTo-Json -Depth 8
