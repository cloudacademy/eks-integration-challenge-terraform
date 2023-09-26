### Provider
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.10.0"
    }
  }
}

locals {
  region = "us-west-2"
}

provider "aws" {
  region = local.region
}

data "aws_availability_zones" "available" {}

locals {
  name        = "cloudacademydevops"
  environment = "prod"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 2)

  iam = {
    cluster_role    = "CLUSTER_IAM_ROLE_ARN"
    node_group_role = "NODE_GROUP_IAM_ROLE_ARN"

  }

  k8s = {
    cluster_name   = "${local.name}-eks-${local.environment}"
    version        = "1.27"
    instance_types = ["t3.small"]
    capacity_type  = "ON_DEMAND"
    disk_size      = 10
    min_size       = 2
    max_size       = 2
    desired_size   = 2
  }
}

#====================================

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = ">= 5.0.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]
  intra_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 52)]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  manage_default_network_acl    = true
  manage_default_route_table    = true
  manage_default_security_group = true

  default_network_acl_tags = {
    Name = "${local.name}-default"
  }

  default_route_table_tags = {
    Name = "${local.name}-default"
  }

  default_security_group_tags = {
    Name = "${local.name}-default"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = {
    Name        = "${local.name}-eks"
    Environment = local.environment
  }
}

module "eks" {
  source = "github.com/cloudacademy/terraform-aws-eks"

  cluster_name    = local.k8s.cluster_name
  cluster_version = local.k8s.version

  cluster_endpoint_public_access   = true
  attach_cluster_encryption_policy = false
  create_iam_role                  = false
  iam_role_arn                     = local.iam.cluster_role

  create_cloudwatch_log_group = false

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    default = {
      name                       = "cloudacademydevops-eks-prod"
      use_custom_launch_template = false
      create_iam_role            = false
      iam_role_arn               = local.iam.node_group_role

      instance_types = local.k8s.instance_types
      capacity_type  = local.k8s.capacity_type

      disk_size = local.k8s.disk_size

      min_size     = local.k8s.min_size
      max_size     = local.k8s.max_size
      desired_size = local.k8s.desired_size

      credit_specification = {
        cpu_credits = "standard"
      }
    }
  }

  //don't do in production - this is for demo/lab purposes only
  create_kms_key            = false
  cluster_encryption_config = {}

  tags = {
    Name        = "${local.name}-eks"
    Environment = local.environment
  }
}
