module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = ">= 6.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr
  azs = var.azs

  public_subnets = var.public_subnet_cidrs
  private_subnets = var.private_subnet_cidrs
  database_subnets = var.db_subnet_cidrs

  enable_nat_gateway = true
  single_nat_gateway = false
  enable_dns_hostnames = true
  enable_dns_support = true

  tags = {
    "Name" = "${var.cluster_name}-vpc"
  }
}

# # VPC Endpoints (PrivateLink / Gateway)

# # S3 Gateway Endpoint (gateway type)
# resource "aws_vpc_endpoint" "s3" {
#   vpc_id = module.vpc.vpc_id
#   service_name = "com.amazonaws.${var.aws_region}.s3"
#   route_table_ids = module.vpc.public_route_table_ids
#   vpc_endpoint_type = "Gateway"
#   tags = { Name = "${var.cluster_name}-s3-vpce" }
# }

# # ECR API (interface)
# resource "aws_vpc_endpoint" "ecr_api" {
#   vpc_id = module.vpc.vpc_id
#   service_name = "com.amazonaws.${var.aws_region}.ecr.api"
#   vpc_endpoint_type = "Interface"
#   subnet_ids = module.vpc.private_subnets
#   security_group_ids = [module.vpc.default_security_group_id]
#   private_dns_enabled = true
#   tags = { Name = "${var.cluster_name}-ecr-api-vpce" }
# }

# # ECR DKR (interface) — container registry layer pulls rely on this + S3
# resource "aws_vpc_endpoint" "ecr_dkr" {
#   vpc_id = module.vpc.vpc_id
#   service_name = "com.amazonaws.${var.aws_region}.ecr.dkr"
#   vpc_endpoint_type = "Interface"
#   subnet_ids = module.vpc.private_subnets
#   security_group_ids = [module.vpc.default_security_group_id]
#   private_dns_enabled = true
#   tags = { Name = "${var.cluster_name}-ecr-dkr-vpce" }
# }

# # STS endpoint (useful for IRSA authentication)
# resource "aws_vpc_endpoint" "sts" {
#   vpc_id = module.vpc.vpc_id
#   service_name = "com.amazonaws.${var.aws_region}.sts"
#   vpc_endpoint_type = "Interface"
#   subnet_ids = module.vpc.private_subnets
#   security_group_ids = [module.vpc.default_security_group_id]
#   private_dns_enabled = true
#   tags = { Name = "${var.cluster_name}-sts-vpce" }
# }

# # ECR repo + S3 bucket


# resource "aws_ecr_repository" "app" {
#   name = "${var.cluster_name}-repo"
#   image_tag_mutability = "MUTABLE"
# }

# resource "aws_s3_bucket" "secrets" {
#   bucket = "${var.cluster_name}-secrets-bucket"
#   acl = "private"
#   versioning {
#     enabled = true
#   }
#   tags = {
#     Name = "${var.cluster_name}-secrets"
#   }
# }

# # restrict S3 access to requests from this VPC endpoint
# data "aws_iam_policy_document" "s3_vpce_policy" {
#   statement {
#     sid = "AllowVPCEOnly"
#     effect = "Deny"
#     actions = ["s3:*"]
#     resources = [
#       aws_s3_bucket.secrets.arn,
#       "${aws_s3_bucket.secrets.arn}/*"
#     ]
    
#     condition {
#       test = "StringNotEquals"
#       variable = "aws:sourceVpce"
#       values = [aws_vpc_endpoint.s3.id]
#     }

#     principals {
#       type = "AWS"
#       identifiers = ["*"]
#     }
#   }
# }

# resource "aws_s3_bucket_policy" "secrets_policy" {
#   bucket = aws_s3_bucket.secrets.id
#   policy = data.aws_iam_policy_document.s3_vpce_policy.json
# }

# ##################################################
# # EKS Cluster (terraform-aws-modules/eks)
# ##################################################

# module "eks" {
#   source = "terraform-aws-modules/eks/aws" 
#   version = ">= 19.0.0"
#   name = var.cluster_name
#   kubernetes_version = "1.33"
#   vpc_id = module.vpc.vpc_id
#   subnet_ids = module.vpc.private_subnets
#   eks_managed_node_groups = {
#    example = {
#      instance_types = ["t3.medium"]
#      min_size       = 1
#      max_size       = 3
#      desired_size   = 2
#    }
#  }

#   # Enable OIDC for IRSA  enable_irsa = true
#   # node groups (managed) - spread across AZs by default  
#   # node_groups = {
#   #   default = {
#   #     desired_capacity = var.node_desired_capacity
#   #     max_capacity = var.node_desired_capacity + 1
#   #     min_capacity = 1
#   #     instance_types = [var.node_instance_type]
#   #     key_name = "" 
#   #     # optional: set your SSH key    
#   #   }
#   # }
#   tags = {
#     "Name" = "${var.cluster_name}-eks"
#   }
# }

# ##################################################
# # IAM Role for pod to access S3 (IRSA example)
# # Create a Kubernetes service account with an IAM role that grants read access to the secrets S3 prefix
# ##################################################

# data "aws_iam_policy_document" "sa_s3_read" {
#   statement {
#     effect = "Allow"
#     actions = [
#       "s3:GetObject",
#       "s3:ListBucket"
#     ]
    
#     resources = [
#       aws_s3_bucket.secrets.arn,
#       "${aws_s3_bucket.secrets.arn}/*"
#       ]
#   }
# }

# resource "aws_iam_role" "irsa_sa_role" {
#   name = "${var.cluster_name}-sa-s3-role"
#   assume_role_policy = data.aws_iam_policy_document.irsa_assume_role.json
#   tags = { Name = "${var.cluster_name}-irsa-sa" }
# }

# data "aws_iam_policy_document" "irsa_assume_role" {
#   statement {
#     effect = "Allow"
#     principals {
#       type = "Federated"
#       identifiers = [module.eks.oidc_provider_arn]
#     }
#     actions = ["sts:AssumeRoleWithWebIdentity"]
#     condition {
#       test = "StringEquals"
#       variable = "${replace(replace(module.eks.cluster_oidc_issuer, "https://", ""), ":", "_")}:sub"
#       values = ["system:serviceaccount:default:app-sa"]
#     }
#   }
# }

# resource "aws_iam_role_policy" "irsa_sa_policy" {
#   role = aws_iam_role.irsa_sa_role.id
#   policy = data.aws_iam_policy_document.sa_s3_read.json
# }

# # Note: Create Kubernetes service account that references this role with the eks module# Many prefer to use module.eks.kubernetes_service_accounts or `kubernetes_service_account` after kubeconfig is available.
# ##################################################
# # RDS PostgreSQL (terraform-aws-modules/rds/aws)
# ##################################################
# -----------------------------------
# module "rds" {
#   source = "terraform-aws-modules/rds/aws"
#   version = ">= 7.0.0"
#   identifier = "${var.cluster_name}-rds"
#   engine = "postgres"
#   engine_version = "15.6"
#   instance_type = "db.t3.medium"
#   allocated_storage = 20
#   name = "appdb"
#   username = var.rds_username
#   password = var.rds_password
#   multi_az = true
#   subnet_ids = module.vpc.database_subnets
#   vpc_security_group_ids = [module.vpc.default_security_group_id]
#   maintenance_window = "Mon:00:00-Mon:03:00"
#   skip_final_snapshot = true
#   tags = {
#     Name = "${var.cluster_name}-rds"
#   }
# }

# ##################################################
# # Security groups adjustments (allow EKS SG -> RDS)
# ##################################################
# # get EKS worker security group (created by module)
# data "aws_security_group" "eks_nodes_sg" {
#   id = module.eks.node_security_group_id
# }
# # Allow RDS to accept from EKS nodes SG
# resource "aws_security_group_rule" "rds_allow_from_eks" {
#   description = "Allow Postgres from EKS nodes"
#   type = "ingress"
#   from_port = 5432
#   to_port = 5432
#   protocol = "tcp"
#   security_group_id = module.rds.security_group_id
#   source_security_group_id = data.aws_security_group.eks_nodes_sg.id
# }

# ##################################################
# # Outputs
# ##################################################

# output "vpc_id" {value = module.vpc.vpc_id}
# output "eks_cluster_name" {value = module.eks.cluster_id}
# output "eks_cluster_endpoint" {value = module.eks.cluster_endpoint}
# output "rds_endpoint" {value = module.rds.address}
# output "s3_bucket" {value = aws_s3_bucket.secrets.bucket}
# output "ecr_repo" {value = aws_ecr_repository.app.repository_url}