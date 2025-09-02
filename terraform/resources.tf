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

resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Allow app traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # Allow private subnet access
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "db_group" {
  name       = "salsify-task-db-subnet-group"
  subnet_ids = module.vpc.database_subnets

  tags = {
    Name = "salsify-task-db-subnet-group"
  }
}

# VPC Endpoints (PrivateLink / Gateway)

# ECR API (interface)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id = module.vpc.vpc_id
  service_name = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type = "Interface"
  subnet_ids = module.vpc.private_subnets
  security_group_ids = [module.vpc.default_security_group_id]
  private_dns_enabled = true
  tags = { Name = "${var.cluster_name}-ecr-api-vpce" }
}

# ECR DKR (interface) — container registry layer pulls rely on this + S3
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id = module.vpc.vpc_id
  service_name = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type = "Interface"
  subnet_ids = module.vpc.private_subnets
  security_group_ids = [module.vpc.default_security_group_id]
  private_dns_enabled = true
  tags = { Name = "${var.cluster_name}-ecr-dkr-vpce" }
}

# STS endpoint (useful for IRSA authentication)
resource "aws_vpc_endpoint" "sts" {
  vpc_id = module.vpc.vpc_id
  service_name = "com.amazonaws.${var.aws_region}.sts"
  vpc_endpoint_type = "Interface"
  subnet_ids = module.vpc.private_subnets
  security_group_ids = [module.vpc.default_security_group_id]
  private_dns_enabled = true
  tags = { Name = "${var.cluster_name}-sts-vpce" }
}

# ECR repo

resource "aws_ecr_repository" "app-ecr" {
  name = "${var.cluster_name}-repo"
  image_tag_mutability = "IMMUTABLE"
}

# # EKS Cluster (terraform-aws-modules/eks)

module "eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"
  name = var.cluster_name
  kubernetes_version = "1.33"
  vpc_id = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  eks_managed_node_groups = {
   example = {
     instance_types = ["t3.medium"]
     min_size       = 1
     max_size       = 3
     desired_size   = 2
   }
 }

  # Enable OIDC for IRSA  enable_irsa = true
  # node groups (managed) - spread across AZs by default  
  # node_groups = {
  #   default = {
  #     desired_capacity = var.node_desired_capacity
  #     max_capacity = var.node_desired_capacity + 1
  #     min_capacity = 1
  #     instance_types = [var.node_instance_type]
  #     key_name = "" 
  #     # optional: set your SSH key    
  #   }
  # }
  tags = {
    "Name" = "${var.cluster_name}-eks"
  }
}

# RDS PostgreSQL (terraform-aws-modules/rds/aws)

module "rds" {
  source = "terraform-aws-modules/rds/aws"
  version = ">=  6.12.0"
  identifier = "${var.cluster_name}-rds"
  engine = "postgres"
  engine_version = "15"
  instance_class = "db.t3.medium"
  allocated_storage = 20
  db_name = "appdb"
  username = var.rds_username
  password = var.rds_password
  multi_az = true
  subnet_ids = module.vpc.database_subnets
  db_subnet_group_name   = aws_db_subnet_group.db_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  maintenance_window = "Mon:00:00-Mon:03:00"
  skip_final_snapshot = true
  family = var.family
  tags = {
    Name = "${var.cluster_name}-rds"
  }
}

# Security groups adjustments (allow EKS SG -> RDS)

# get EKS worker security group (created by module)
data "aws_security_group" "eks_nodes_sg" {
  id = module.eks.node_security_group_id
}
# Allow RDS to accept from EKS nodes SG
resource "aws_security_group_rule" "rds_allow_from_eks" {
  description = "Allow Postgres from EKS nodes"
  type = "ingress"
  from_port = 5432
  to_port = 5432
  protocol = "tcp"
  security_group_id = module.rds.security_group_id
  source_security_group_id = data.aws_security_group.eks_nodes_sg.id
}

# Outputs

# output "vpc_id" {value = module.vpc.default_security_group_id}
# output "eks_cluster_name" {value = module.eks.cluster_id}
# output "eks_cluster_endpoint" {value = module.eks.cluster_endpoint}
# output "rds_endpoint" {value = module.rds.address}
# output "s3_bucket" {value = aws_s3_bucket.secrets.bucket}
# output "ecr_repo" {value = aws_ecr_repository.app-ecr.repository_url}
