locals {
  public_subnet_cidrs  = [for index in range(2) : cidrsubnet(var.vpc_cidr, 8, index)]
  private_subnet_cidrs = [for index in range(2) : cidrsubnet(var.vpc_cidr, 8, index + 2)]
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { Name = var.name })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-igw" })
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.this.id
  availability_zone       = var.availability_zones[count.index]
  cidr_block              = local.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  tags = merge(var.tags, {
    Name                     = "${var.name}-public-${count.index + 1}"
    "kubernetes.io/role/elb" = "1"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-public" })
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_subnet" "private" {
  count = var.create_private_subnets ? 2 : 0

  vpc_id                  = aws_vpc.this.id
  availability_zone       = var.availability_zones[count.index]
  cidr_block              = local.private_subnet_cidrs[count.index]
  map_public_ip_on_launch = false
  tags = merge(var.tags, {
    Name                              = "${var.name}-private-${count.index + 1}"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

resource "aws_route_table" "private" {
  count = var.create_private_subnets ? 1 : 0

  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-private" })
}

resource "aws_route_table_association" "private" {
  count = var.create_private_subnets ? 2 : 0

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[0].id
}
