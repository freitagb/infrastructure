// Find out which subnets and security group our EFS mount target should be in
// It needs to be in the public subnet where our nodes are, as the nodes will be
// doing the mounting operation. It should be in a security group shared by all
// the nodes. We create a mount target in each subnet, even if we primarily put
// all our nodes in one - this allows for GPU nodes to be spread out across
// AZ when needed
data "aws_subnets" "cluster_node_subnets" {

  filter {
    name   = "vpc-id"
    values = [data.aws_eks_cluster.cluster.vpc_config[0]["vpc_id"]]
  }

  filter {
    name   = "tag:aws:cloudformation:logical-id"
    values = ["SubnetPublic*"]
  }

  filter {
    name   = "tag:eksctl.cluster.k8s.io/v1alpha1/cluster-name"
    values = [var.cluster_name]
  }
}

data "aws_security_group" "cluster_nodes_shared_security_group" {

  filter {
    name   = "vpc-id"
    values = [data.aws_eks_cluster.cluster.vpc_config[0]["vpc_id"]]
  }
  filter {
    name   = "tag:aws:cloudformation:logical-id"
    values = ["ClusterSharedNodeSecurityGroup"]
  }

  filter {
    name   = "tag:eksctl.cluster.k8s.io/v1alpha1/cluster-name"
    values = [var.cluster_name]
  }
}

resource "aws_efs_file_system" "homedirs" {
  for_each = var.filestores
  tags = merge(var.tags, {
    Name = each.value.name_suffix == null ? "hub-homedirs" : "hub-homedirs-${each.value.name_suffix}"
  })

  # Transition files to a slower, cheaper backing medium 90 days
  # after they were last *accessed*. They will be transferred back to regular
  # backing medium immediately on access. This saves a *lot* of money with
  # barely perceptible user performance hit. 90 days is the longest config,
  # and we can start here to be conservative. IA (Infrequent Access) is
  # documented in https://aws.amazon.com/efs/features/infrequent-access/
  # These need to be two different blocks, see
  # https://github.com/hashicorp/terraform-provider-aws/issues/21862#issuecomment-1007115545
  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  lifecycle_policy {
    transition_to_ia = "AFTER_90_DAYS"
  }

  lifecycle {
    # Additional safeguard against deleting the EFS
    # as this causes irreversible data loss!
    prevent_destroy = true
  }
}

locals {
  fs_ids       = toset(values(aws_efs_file_system.homedirs)[*].id)
  fs_dns_names = toset(values(aws_efs_file_system.homedirs)[*].dns_name)

  subnet_ids = toset(data.aws_subnets.cluster_node_subnets.ids)

  efs_mount_targets = [
    for pair in setproduct(local.subnet_ids, local.fs_ids) : {
      file_system_id = pair[0]
      subnet_id      = pair[1]
    }
  ]
}
resource "aws_efs_mount_target" "homedirs" {
  for_each = tomap({
    for mount_target in local.efs_mount_targets : "${mount_target.subnet_id}.${mount_target.file_system_id}" => mount_target
  })

  file_system_id  = each.value.file_system_id
  subnet_id       = each.value.subnet_id
  security_groups = [data.aws_security_group.cluster_nodes_shared_security_group.id]
}

output "nfs_server_dns" {
  value = values(aws_efs_file_system.homedirs)[*].dns_name
}

# Enable automatic backups for user homedirectories
# Documented in https://docs.aws.amazon.com/efs/latest/ug/awsbackup.html#automatic-backups
resource "aws_efs_backup_policy" "homedirs" {
  for_each       = aws_efs_file_system.homedirs
  file_system_id = each.value.id

  backup_policy {
    status = "ENABLED"
  }
}
