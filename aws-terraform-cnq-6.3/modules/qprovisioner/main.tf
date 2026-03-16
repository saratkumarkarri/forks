#MIT License

#Copyright (c) 2025 Qumulo, Inc.

#Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the Software), to deal 
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is 
# furnished to do so, subject to the following conditions:

#The above copyright notice and this permission notice shall be included in all 
#copies or substantial portions of the Software.

#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE 
#SOFTWARE.

data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "existing-deployment-cluster-iam-role" {
  count = var.replacement_cluster ? 1 : 0

  name            = "/qumulo/${var.existing_deployment_unique_name}/cluster-iam-role"
  with_decryption = true
}

data "aws_ssm_parameter" "existing-deployment-provisioner-iam-role" {
  count = var.replacement_cluster ? 1 : 0

  name            = "/qumulo/${var.existing_deployment_unique_name}/provisioner-iam-role"
  with_decryption = true
}

data "aws_ssm_parameter" "existing-deployment-number-float-ips" {
  count = var.replacement_cluster ? 1 : 0

  name            = "/qumulo/${var.existing_deployment_unique_name}/number-float-ips"
  with_decryption = true
}

data "aws_iam_policy" "secrets" {
  arn = "arn:${var.aws_partition}:iam::aws:policy/SecretsManagerReadWrite"
}

data "aws_iam_policy" "ssmrole" {
  arn = "arn:${var.aws_partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_ami" "ubuntu" {
  count = var.ami_id == null ? 1 : 0
    
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ami" "rocky" {
  count = var.ami_id == null ? 1 : 0

  most_recent = true
  owners      = ["792107900819"] # Rocky

  filter {
    name   = "name"
    values = ["Rocky-9-EC2-Base-9.5*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  cluster_persistent_bucket_names = tolist(split(", ", var.cluster_persistent_bucket_names))

  existing_deployment_cluster_iam_role     = var.replacement_cluster ? nonsensitive(data.aws_ssm_parameter.existing-deployment-cluster-iam-role[0].value) : ""
  existing_deployment_provisioner_iam_role = var.replacement_cluster ? nonsensitive(data.aws_ssm_parameter.existing-deployment-provisioner-iam-role[0].value) : ""

  # ARNs for KMS and CMK
  kms_arn   = var.kms_key_id == null ? "*" : "arn:${var.aws_partition}:kms:${var.aws_region}:${var.aws_account_id}:key/${var.kms_key_id}"
  allow_cmk = var.kms_key_id == null ? "Deny" : "Allow"

  #Select deb or rpm user data template and ami
  user_data_template = var.debian_package ? "${var.scripts_path}user-data-deb.sh" : "${var.scripts_path}user-data-rpm.sh"
  ami_id             = var.ami_id == null ? (var.debian_package ? data.aws_ami.ubuntu.0.id : data.aws_ami.rocky.0.id) : var.ami_id

  #Security Group Rules
  ingress_rules = [
    {
      port        = 22
      description = "TCP ports for SSH"
      protocol    = "tcp"
    },
    {
      port        = 80
      description = "TCP ports for HTTP"
      protocol    = "tcp"
    },
    {
      port        = 443
      description = "TCP ports for HTTPS"
      protocol    = "tcp"
    }
  ]
}

resource "aws_security_group" "provisioner" {
  name        = "${var.deployment_unique_name}-qumulo-provisioner"
  description = "Enable ports to provisioner instance"
  vpc_id      = var.aws_vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = local.ingress_rules
    content {
      cidr_blocks = var.cluster_sg_cidrs
      description = ingress.value.description
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = ingress.value.protocol
    }
  }

  tags = merge(var.tags, { Name = "${var.deployment_unique_name}" })
}

resource "aws_iam_role" "provisioner_access" {
  name = "${var.deployment_unique_name}-qumulo-provisioner"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Sid": ""
    }
  ]
}
EOF

  permissions_boundary = var.permissions_boundary == null ? null : "arn:${var.aws_partition}:iam::${var.aws_account_id}:policy/${var.permissions_boundary}"
}

resource "aws_iam_instance_profile" "provisioner_access" {
  name = "${var.deployment_unique_name}-qumulo-provisioner"
  role = aws_iam_role.provisioner_access.name
}

resource "aws_iam_role_policy_attachment" "secrets" {
  role       = aws_iam_role.provisioner_access.name
  policy_arn = data.aws_iam_policy.secrets.arn
}

resource "aws_iam_role_policy_attachment" "ssmrole" {
  role       = aws_iam_role.provisioner_access.name
  policy_arn = data.aws_iam_policy.ssmrole.arn
}

resource "aws_iam_role_policy" "policy1" {
  name   = "s3-policy"
  role   = aws_iam_role.provisioner_access.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",        
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:${var.aws_partition}:s3:::${var.s3_bucket_name}/*",
        "arn:${var.aws_partition}:s3:::${var.s3_bucket_name}"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "policy2" {
  name   = "EC2-SSM-policy"
  role   = aws_iam_role.provisioner_access.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudformation:DescribeStackResource",
        "cloudformation:DescribeStackResources",
        "cloudformation:DescribeStacks",
        "cloudformation:SetStackPolicy",
        "cloudformation:UpdateTerminationProtection",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:DescribeTags",
        "ec2:DescribeInstances",
        "ec2:DescribeVolumes",
        "ec2:ModifyInstanceAttribute",
        "ec2:ModifyNetworkInterfaceAttribute",
        "ec2:ModifyVolume",
        "kms:Decrypt",
        "ssm:GetParameter",
        "ssm:ListCommandInvocations",
        "ssm:ListInstanceAssociations",
        "ssm:PutParameter",
        "ssm:UpdateInstanceInformation",
        "ssm:SendCommand"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "policy3" {
  name   = "CMK-S3-policy"
  role   = aws_iam_role.provisioner_access.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",        
      "Action": [
        "kms:CreateGrant",
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:GenerateDataKey",
        "kms:ReEncryptFrom",
        "kms:ReEncryptTo"
      ],
      "Resource": "${var.kms_s3_arn}"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "policy4" {
  name   = "S3-persistent-policy"
  role   = aws_iam_role.provisioner_access.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",        
      "Action": [
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": ${var.cluster_persistent_bucket_arns_json}
    }
  ]
}
EOF
}

resource "aws_s3_bucket_policy" "qumulo-persistent-storage" {
  count = var.cluster_persistent_bucket_policy && !var.replacement_cluster ? length(local.cluster_persistent_bucket_names) : 0

  bucket = local.cluster_persistent_bucket_names[count.index]
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Allow-Deployment-User",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${data.aws_caller_identity.current.arn}"
      },
      "Action": "s3:*",
      "Resource": [
        "arn:${var.aws_partition}:s3:::${local.cluster_persistent_bucket_names[count.index]}",
        "arn:${var.aws_partition}:s3:::${local.cluster_persistent_bucket_names[count.index]}/*" 
      ],
			"Condition": {
				"Bool": {
					"aws:SecureTransport": "true"
				}
			}      
    },    
    {
      "Sid": "Allow-Provisioner",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${aws_iam_role.provisioner_access.arn}"
      },
      "Action": [
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:${var.aws_partition}:s3:::${local.cluster_persistent_bucket_names[count.index]}",
        "arn:${var.aws_partition}:s3:::${local.cluster_persistent_bucket_names[count.index]}/*" 
      ],
			"Condition": {
				"Bool": {
					"aws:SecureTransport": "true"
				}
			}      
    },
    {
      "Sid": "Allow-Cluster",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${var.cluster_iam_role_arn}"
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:${var.aws_partition}:s3:::${local.cluster_persistent_bucket_names[count.index]}",
        "arn:${var.aws_partition}:s3:::${local.cluster_persistent_bucket_names[count.index]}/*" 
      ],
			"Condition": {
				"Bool": {
					"aws:SecureTransport": "true"
				}
			}      
    },
     {
            "Sid": "MustBeEncryptedInTransit",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
              "arn:${var.aws_partition}:s3:::${local.cluster_persistent_bucket_names[count.index]}",
              "arn:${var.aws_partition}:s3:::${local.cluster_persistent_bucket_names[count.index]}/*" 
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        }    
  ]
}
EOF
}

resource "aws_s3_bucket_policy" "qumulo-persistent-storage-combo" {
  count = var.cluster_persistent_bucket_policy && var.replacement_cluster ? length(local.cluster_persistent_bucket_names) : 0

  bucket = local.cluster_persistent_bucket_names[count.index]
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Allow-Deployment-User",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${data.aws_caller_identity.current.arn}"
      },
      "Action": "s3:*",
      "Resource": [
        "arn:${var.aws_partition}:s3:::${local.cluster_persistent_bucket_names[count.index]}",
        "arn:${var.aws_partition}:s3:::${local.cluster_persistent_bucket_names[count.index]}/*" 
      ],
			"Condition": {
				"Bool": {
					"aws:SecureTransport": "true"
				}
			}      
    },    
    {
      "Sid": "Allow-New-Provisioner",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${aws_iam_role.provisioner_access.arn}"
      },
      "Action": [
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:${var.aws_partition}:s3:::${local.cluster_persistent_bucket_names[count.index]}",
        "arn:${var.aws_partition}:s3:::${local.cluster_persistent_bucket_names[count.index]}/*" 
      ],
			"Condition": {
				"Bool": {
					"aws:SecureTransport": "true"
				}
			}      
    },
    {
      "Sid": "Allow-New-Cluster",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${var.cluster_iam_role_arn}"
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:${var.aws_partition}:s3:::${local.cluster_persistent_bucket_names[count.index]}",
        "arn:${var.aws_partition}:s3:::${local.cluster_persistent_bucket_names[count.index]}/*" 
      ],
			"Condition": {
				"Bool": {
					"aws:SecureTransport": "true"
				}
			}      
    },
    {
      "Sid": "Allow-Existing-Provisioner",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${local.existing_deployment_provisioner_iam_role}"
      },
      "Action": [
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:${var.aws_partition}:s3:::${local.cluster_persistent_bucket_names[count.index]}",
        "arn:${var.aws_partition}:s3:::${local.cluster_persistent_bucket_names[count.index]}/*" 
      ],
			"Condition": {
				"Bool": {
					"aws:SecureTransport": "true"
				}
			}      
    },
    {
      "Sid": "Allow-Existing-Cluster",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${local.existing_deployment_cluster_iam_role}"
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:${var.aws_partition}:s3:::${local.cluster_persistent_bucket_names[count.index]}",
        "arn:${var.aws_partition}:s3:::${local.cluster_persistent_bucket_names[count.index]}/*" 
      ],
			"Condition": {
				"Bool": {
					"aws:SecureTransport": "true"
				}
			}      
    },
    {
            "Sid": "MustBeEncryptedInTransit",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
              "arn:${var.aws_partition}:s3:::${local.cluster_persistent_bucket_names[count.index]}",
              "arn:${var.aws_partition}:s3:::${local.cluster_persistent_bucket_names[count.index]}/*" 
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        }            
  ]
}
EOF
}

resource "aws_ssm_parameter" "creation-number-AZs" {
  name  = "/qumulo/${var.deployment_unique_name}/creation-number-AZs"
  type  = "SecureString"
  value = "null"
  lifecycle { ignore_changes = [value] }
}
resource "aws_ssm_parameter" "creation-version" {
  name  = "/qumulo/${var.deployment_unique_name}/creation-version"
  type  = "SecureString"
  value = "null"
  lifecycle { ignore_changes = [value] }
}
resource "aws_ssm_parameter" "installed-version" {
  name  = "/qumulo/${var.deployment_unique_name}/installed-version"
  type  = "SecureString"
  value = "null"
  lifecycle { ignore_changes = [value] }
}
resource "aws_ssm_parameter" "cluster-type" {
  name  = "/qumulo/${var.deployment_unique_name}/cluster-type"
  type  = "SecureString"
  value = "null"
  lifecycle { ignore_changes = [value] }
}
resource "aws_ssm_parameter" "cluster-iam-role" {
  name  = "/qumulo/${var.deployment_unique_name}/cluster-iam-role"
  type  = "SecureString"
  value = var.cluster_iam_role_arn
  lifecycle { ignore_changes = [value] }
}
resource "aws_ssm_parameter" "provisioner-iam-role" {
  name  = "/qumulo/${var.deployment_unique_name}/provisioner-iam-role"
  type  = "SecureString"
  value = aws_iam_role.provisioner_access.arn
  lifecycle { ignore_changes = [value] }
}
resource "aws_ssm_parameter" "cluster-secrets-arn" {
  name  = "/qumulo/${var.deployment_unique_name}/cluster-secrets-arn"
  type  = "SecureString"
  value = var.cluster_secrets_arn
  lifecycle { ignore_changes = [value] }
}
resource "aws_ssm_parameter" "bucket-uris" {
  name  = "/qumulo/${var.deployment_unique_name}/bucket-uris"
  type  = "SecureString"
  value = "null"
  lifecycle { ignore_changes = [value] }
}
resource "aws_ssm_parameter" "bucket-names" {
  name  = "/qumulo/${var.deployment_unique_name}/bucket-names"
  type  = "SecureString"
  value = "null"
  lifecycle { ignore_changes = [value] }
}
resource "aws_ssm_parameter" "soft-capacity-limit" {
  name  = "/qumulo/${var.deployment_unique_name}/soft-capacity-limit"
  type  = "SecureString"
  value = "null"
  lifecycle { ignore_changes = [value] }
}
resource "aws_ssm_parameter" "tunables" {
  name  = "/qumulo/${var.deployment_unique_name}/tunables"
  type  = "SecureString"
  value = "null"
  lifecycle { ignore_changes = [value] }
}
resource "aws_ssm_parameter" "fault-domain-ids" {
  name  = "/qumulo/${var.deployment_unique_name}/fault-domain-ids"
  type  = "SecureString"
  value = "null"
  lifecycle { ignore_changes = [value] }
}
resource "aws_ssm_parameter" "instance-ids" {
  name  = "/qumulo/${var.deployment_unique_name}/instance-ids"
  type  = "SecureString"
  value = "null"
  lifecycle { ignore_changes = [value] }
}
resource "aws_ssm_parameter" "node-ips" {
  name  = "/qumulo/${var.deployment_unique_name}/node-ips"
  type  = "SecureString"
  value = "null"
  lifecycle { ignore_changes = [value] }
}
resource "aws_ssm_parameter" "float-ips" {
  name  = "/qumulo/${var.deployment_unique_name}/float-ips"
  type  = "SecureString"
  value = "null"
  lifecycle { ignore_changes = [value] }
}
resource "aws_ssm_parameter" "uuid" {
  name  = "/qumulo/${var.deployment_unique_name}/uuid"
  type  = "SecureString"
  value = "null"
  lifecycle { ignore_changes = [value] }
}
resource "aws_ssm_parameter" "last-run-status" {
  name  = "/qumulo/${var.deployment_unique_name}/last-run-status"
  type  = "SecureString"
  value = "null"
  lifecycle { ignore_changes = [value] }
}
resource "aws_ssm_parameter" "max-float-ips" {
  name  = "/qumulo/${var.deployment_unique_name}/max-float-ips"
  type  = "SecureString"
  value = "null"
  lifecycle { ignore_changes = [value] }
}
resource "aws_ssm_parameter" "number-float-ips" {
  name  = "/qumulo/${var.deployment_unique_name}/number-float-ips"
  type  = "SecureString"
  value = "null"
  lifecycle { ignore_changes = [value] }
}

resource "aws_network_interface" "provisioner" {
  security_groups = var.cluster_additional_sg_ids == [] ? [aws_security_group.provisioner.id] : concat([aws_security_group.provisioner.id], var.cluster_additional_sg_ids)

  subnet_id = var.private_subnet_id

  tags = merge(var.tags, { Name = "${var.deployment_unique_name}-provisioner}" })
}

resource "aws_instance" "provisioner" {
  ami                     = local.ami_id
  disable_api_termination = false
  ebs_optimized           = true
  iam_instance_profile    = aws_iam_instance_profile.provisioner_access.name
  instance_type           = var.instance_type
  key_name                = var.ec2_key_pair
  user_data = templatefile("${local.user_data_template}", {
    bucket_name                               = var.s3_bucket_name
    bucket_region                             = var.s3_bucket_region
    cluster_fqdn                              = var.cluster_fqdn == null || join(",", var.cluster_floating_ips) == "" ? "" : var.cluster_fqdn
    cluster_name                              = var.cluster_name
    cluster_secrets_arn                       = var.cluster_secrets_arn
    cluster_sg_id                             = var.cluster_sg_id
    cluster_persistent_bucket_uris            = var.cluster_persistent_bucket_uris
    cluster_persistent_bucket_names           = var.cluster_persistent_bucket_names
    cluster_persistent_storage_capacity_limit = var.cluster_persistent_storage_capacity_limit
    cluster_persistent_storage_type           = var.cluster_persistent_storage_type
    deployment_unique_name                    = var.deployment_unique_name
    ena_express                               = var.ena_express
    existing_deployment_unique_name           = var.existing_deployment_unique_name == null ? "" : var.existing_deployment_unique_name
    fault_domain_ids                          = join(",", var.cluster_fault_domain_ids)
    flash_tput                                = var.flash_tput
    flash_iops                                = var.flash_iops
    floating_ips                              = join(",", var.cluster_floating_ips)
    functions_s3_prefix                       = var.functions_s3_prefix
    install_s3_prefix                         = var.install_s3_prefix
    instance_ids                              = join(",", var.cluster_instance_ids)
    max_floating_ips                          = var.cluster_max_floating_ips
    node1_ip                                  = var.cluster_node1_ip
    number_azs                                = tostring(var.aws_number_azs)
    primary_ips                               = join(",", var.cluster_primary_ips)
    region                                    = var.aws_region
    replacement_cluster                       = var.replacement_cluster
    scripts_path                              = var.scripts_path
    scripts_s3_prefix                         = var.scripts_s3_prefix
    target_node_count                         = var.target_node_count == null ? 0 : var.target_node_count
    temporary_password                        = var.cluster_temporary_password
    tun_refill_IOPS                           = var.tun_refill_IOPS
    tun_refill_Bps                            = var.tun_refill_Bps
    tun_EBS_BW                                = var.tun_EBS_BW
    tun_EC2_BW                                = var.tun_EC2_BW
    tun_disk_count                            = var.tun_disk_count
    version                                   = var.cluster_version
  })

  tags = merge(var.tags, { Name = "${var.deployment_unique_name}-provisioner" })

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.provisioner.id
  }

  root_block_device {
    encrypted   = true
    kms_key_id  = var.kms_key_id == null ? "" : "arn:${var.aws_partition}:kms:${var.aws_region}:${var.aws_account_id}:key/${var.kms_key_id}"
    volume_type = var.boot_type
    volume_size = var.boot_volume_size

    tags = merge(var.tags, { Name = "${var.deployment_unique_name}-provisioner" })
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 3
    http_tokens                 = var.require_imdsv2 ? "required" : "optional"
  }

  lifecycle {
    ignore_changes = [root_block_device[0].kms_key_id]
  }
}

#This resource monitors the status of the qprovisioner module (EC2 Instance) that executes secondary provisioning of the Qumulo cluster.
#It pulls status from SSM Parameter Store where the provisioner writest status/state.

locals {
  is_windows  = substr(pathexpand("~"), 0, 1) == "/" ? false : true
  status_sh   = "${var.scripts_path}status.sh"
  status_ps1  = "${var.scripts_path}status.ps1"
  status_vars = { aws_region = var.aws_region, deployment_unique_name = var.deployment_unique_name, aws_instance_id = aws_instance.provisioner.id }
}

data "aws_ssm_parameter" "qprovisioner" {
  count = var.check_provisioner_shutdown ? 1 : 0

  name            = "/qumulo/${var.deployment_unique_name}/last-run-status"
  with_decryption = true

  depends_on = [null_resource.provisioner_status]
}

data "aws_ssm_parameter" "floating-ips" {
  count = var.check_provisioner_shutdown ? 1 : 0

  name            = "/qumulo/${var.deployment_unique_name}/float-ips"
  with_decryption = true

  depends_on = [null_resource.provisioner_status]
}

data "aws_ssm_parameter" "node-ips" {
  count = var.check_provisioner_shutdown ? 1 : 0

  name            = "/qumulo/${var.deployment_unique_name}/node-ips"
  with_decryption = true

  depends_on = [null_resource.provisioner_status]
}

resource "null_resource" "provisioner_status" {
  count = var.check_provisioner_shutdown ? 1 : 0

  provisioner "local-exec" {
    quiet       = true
    interpreter = local.is_windows ? ["PowerShell", "-Command"] : []
    command     = local.is_windows ? templatefile(local.status_ps1, local.status_vars) : templatefile(local.status_sh, local.status_vars)
  }

  triggers = {
    script_hash = "${sha256("${aws_instance.provisioner.user_data}")}"
  }

  depends_on = [aws_instance.provisioner]
}
