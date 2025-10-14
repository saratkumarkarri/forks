#MIT License

#Copyright (c) 2025 Qumulo, Inc.

#Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the Software), to deal 
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is 
# furnished to do so, subject to the following conditions =

#The above copyright notice and this permission notice shall be included in all 
#copies or substantial portions of the Software.

#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE 
#SOFTWARE.

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

#Create a parameter indicating this is a new cluster that is only set on initial creation
resource "aws_ssm_parameter" "new-cluster" {
  name  = "/qumulo/${var.deployment_unique_name}/new-cluster"
  type  = "SecureString"
  value = "true"
  lifecycle { ignore_changes = [value] }
}

data "aws_ssm_parameter" "new-cluster" {
  name            = "/qumulo/${var.deployment_unique_name}/new-cluster"
  with_decryption = true

  depends_on = [aws_ssm_parameter.new-cluster]
}

#Only grab these parameters if this is a replacement cluster or not a new cluster.  The final data source read of new-cluster is just to make terraform happy.  Can't use count here on these resources because of the dependency loop. Bogus data is negated with logic in locals.
data "aws_ssm_parameter" "instance-ids" {
  name            = var.replacement_cluster ? "/qumulo/${var.existing_deployment_unique_name}/instance-ids" : (!local.new_cluster ? "/qumulo/${var.deployment_unique_name}/instance-ids" : "/qumulo/${var.deployment_unique_name}/new-cluster")
  with_decryption = true

  depends_on = [aws_ssm_parameter.new-cluster]
}

data "aws_ssm_parameter" "number-float-ips" {
  name            = var.replacement_cluster ? "/qumulo/${var.existing_deployment_unique_name}/number-float-ips" : (!local.new_cluster ? "/qumulo/${var.deployment_unique_name}/number-float-ips" : "/qumulo/${var.deployment_unique_name}/new-cluster")
  with_decryption = true

  depends_on = [aws_ssm_parameter.new-cluster]
}

data "aws_ssm_parameter" "float-ips" {
  name            = var.replacement_cluster ? "/qumulo/${var.existing_deployment_unique_name}/float-ips" : (!local.new_cluster ? "/qumulo/${var.deployment_unique_name}/float-ips" : "/qumulo/${var.deployment_unique_name}/new-cluster")
  with_decryption = true

  depends_on = [aws_ssm_parameter.new-cluster]
}

data "aws_ssm_parameter" "creation-number-azs" {
  name            = var.replacement_cluster ? "/qumulo/${var.existing_deployment_unique_name}/creation-number-AZs" : (!local.new_cluster ? "/qumulo/${var.deployment_unique_name}/creation-number-AZs" : "/qumulo/${var.deployment_unique_name}/new-cluster")
  with_decryption = true

  depends_on = [aws_ssm_parameter.new-cluster]
}

locals {
  # Read in relevant paramters for FIPS
  new_cluster         = nonsensitive(data.aws_ssm_parameter.new-cluster.value) == "true" ? true : false
  existing_node_count = !local.new_cluster || var.replacement_cluster ? length(tolist(split(",", nonsensitive(data.aws_ssm_parameter.instance-ids.value)))) : 0
  existing_fips       = !local.new_cluster || var.replacement_cluster ? (nonsensitive(data.aws_ssm_parameter.number-float-ips.value) == "null" ? 0 : tonumber(nonsensitive(data.aws_ssm_parameter.number-float-ips.value))) : 0
  existing_maz        = !local.new_cluster || var.replacement_cluster ? (nonsensitive(data.aws_ssm_parameter.creation-number-azs.value) > 1 ? true : false) : false
  existing_fips_list  = var.replacement_cluster ? tolist(split(",", nonsensitive(data.aws_ssm_parameter.float-ips.value))) : null
  max_node_fips       = lookup(var.ec2_map[var.instance_type], "maxSecIPs")

  # Check to make sure cluster reduction in node count is valid
  check_cluster_remove_nodes = local.new_cluster ? false : (local.existing_node_count > var.node_count ? true : false)

  # Check to make sure a new TF workspace is being used (ie new state) for a replacement cluster
  check_workspace_on_replace = var.replacement_cluster && var.existing_deployment_unique_name == var.deployment_unique_name ? true : false

  # Build additional conditionals for node adds on single AZ clusters 
  # remove-nodes.sh validates remove scenarios when not doing a cluster replace to make sure the # of floaters can be supported.  
  # SAZ to SAZ cluster replace is error checked by the provisioner for # floater support because dependencies in TF prevent error checking here.
  # SAZ to MAZ or a new MAZ deployment negates floaters.
  # The ultimate outcome is clusters will get provisioned with the number of intiital floating IPs specifed or the min per node required.  Floaters will be added if necessary when clusters are grown.
  add_to_saz         = !local.new_cluster && !var.replacement_cluster && var.aws_number_azs == 1 && var.node_count > local.existing_node_count ? true : false
  replace_saz_to_saz = local.new_cluster && var.replacement_cluster && !local.existing_maz && var.aws_number_azs == 1 ? true : false

  # Do FIPS math
  min_fips = var.node_count * var.cluster_min_floating_ips_per_node < var.cluster_initial_floating_ips ? var.cluster_initial_floating_ips : var.node_count * var.cluster_min_floating_ips_per_node
  new_fips = local.min_fips > local.existing_fips ? local.min_fips - local.existing_fips : 0
  max_fips = var.node_count * local.max_node_fips

  # Apply FIPS in chunks for new clusters or nodes
  new_nodes_with_max_fips = floor(local.new_fips / local.max_node_fips)
  new_remaining_fips      = local.new_fips - (local.new_nodes_with_max_fips * local.max_node_fips)

  # Build a list with the FIPS per node
  node_fips = var.cluster_initial_floating_ips == 0 || var.aws_number_azs > 1 ? [for n in range(var.node_count) : 0] : (local.add_to_saz || local.replace_saz_to_saz ? [
    for n in range(var.node_count) : n == 0 ? 0 : (n < local.existing_node_count ? 0 : (n < local.existing_node_count + local.new_nodes_with_max_fips ? local.max_node_fips : (n < local.existing_node_count + local.new_nodes_with_max_fips + 1 ? local.new_remaining_fips : 0)))
    ] : [
    for n in range(var.node_count) : n == 0 ? 0 : (n < local.new_nodes_with_max_fips + 1 ? local.max_node_fips : (n < local.new_nodes_with_max_fips + 2 ? local.new_remaining_fips : 0))
    ]
  )

  # Check the instance type to make sure it is large enough for the soft capacity limit
  capacity_limit_tb           = var.cluster_persistent_storage_capacity_limit / 1000 / 1000 / 1000 / 1000
  capacity_per_node_needed    = var.target_node_count == null || var.replacement_cluster ? local.capacity_limit_tb / var.node_count : local.capacity_limit_tb / var.target_node_count
  capacity_per_node_available = lookup(var.ec2_map[var.instance_type], "nodeCap")
  capacity_unconstrained      = local.capacity_per_node_needed <= local.capacity_per_node_available ? true : false

  # Persistent storage bucket ARN wildcards
  persistent_bucket_arns_1    = formatlist("%s/*", tolist(split(", ", var.persistent_bucket_arns)))
  persistent_bucket_arns_2    = tolist(split(", ", var.persistent_bucket_arns))
  persistent_bucket_arns      = concat(local.persistent_bucket_arns_1, local.persistent_bucket_arns_2)
  persistent_bucket_arns_json = jsonencode(local.persistent_bucket_arns)

  #Key ARNs to support default or CMK
  kms_ebs_arn = var.kms_key_id == null ? "arn:${var.aws_partition}:kms:${var.aws_region}:${var.aws_account_id}:alias/aws/ebs" : "arn:${var.aws_partition}:kms:${var.aws_region}:${var.aws_account_id}:key/${var.kms_key_id}"
  kms_s3_arn  = var.kms_key_id == null ? "arn:${var.aws_partition}:kms:${var.aws_region}:${var.aws_account_id}:alias/aws/s3" : "arn:${var.aws_partition}:kms:${var.aws_region}:${var.aws_account_id}:key/${var.kms_key_id}"

  #Package Install S3 bucket/prefix
  install_s3_arn    = "arn:${var.aws_partition}:s3:::${var.s3_bucket_name}/${var.install_s3_prefix}"
  install_s3_prefix = "${var.install_s3_prefix}/${var.cluster_version}/"

  #Select deb or rpm user data template and ami
  user_data_template = var.debian_package ? "${var.cluster_scripts_path}user-data-deb.sh" : "${var.cluster_scripts_path}user-data-rpm.sh"
  ami_id             = var.ami_id == null ? (var.debian_package ? data.aws_ami.ubuntu.0.id : data.aws_ami.rocky.0.id) : var.ami_id

  device_names = [
    "/dev/xvdb",
    "/dev/xvdc",
    "/dev/xvdd",
    "/dev/xvde",
    "/dev/xvdf",
    "/dev/xvdg",
    "/dev/xvdh",
    "/dev/xvdi",
    "/dev/xvdj",
    "/dev/xvdk",
    "/dev/xvdl",
    "/dev/xvdm",
    "/dev/xvdn",
    "/dev/xvdo",
    "/dev/xvdp",
    "/dev/xvdq",
    "/dev/xvdr",
    "/dev/xvds",
    "/dev/xvdt",
    "/dev/xvdu",
    "/dev/xvdv",
    "/dev/xvdw",
    "/dev/xvdx",
    "/dev/xvdy",
    "/dev/xvdz",
    "/dev/xvdaa",
    "/dev/xvdab",
    "/dev/xvdac",
    "/dev/xvdad",
    "/dev/xvdae",
    "/dev/xvdaf",
    "/dev/xvdag",
    "/dev/xvdah",
    "/dev/xvdai",
    "/dev/xvdaj",
    "/dev/xvdak",
    "/dev/xvdal",
    "/dev/xvdam",
    "/dev/xvdan",
    "/dev/xvdao",
    "/dev/xvdap",
    "/dev/xvdaq",
    "/dev/xvdar",
    "/dev/xvdas",
    "/dev/xvdat",
    "/dev/xvdau",
    "/dev/xvdav",
    "/dev/xvdaw",
    "/dev/xvdax",
    "/dev/xvdba",
    "/dev/xvdbb",
    "/dev/xvdbc",
    "/dev/xvdbd",
    "/dev/xvdbe",
    "/dev/xvdbf",
    "/dev/xvdbg",
    "/dev/xvdbh",
    "/dev/xvdbi",
    "/dev/xvdbj",
    "/dev/xvdbk",
    "/dev/xvdbl",
    "/dev/xvdbm",
    "/dev/xvdbn",
    "/dev/xvdbo",
    "/dev/xvdbp",
    "/dev/xvdbq",
    "/dev/xvdbr",
    "/dev/xvdbs",
    "/dev/xvdbt",
    "/dev/xvdbu",
    "/dev/xvdbv",
    "/dev/xvdbw",
    "/dev/xvdbx",
    "/dev/xvdca",
    "/dev/xvdcb",
    "/dev/xvdcc",
    "/dev/xvdcd",
    "/dev/xvdce",
    "/dev/xvdcf",
    "/dev/xvdcg",
    "/dev/xvdch",
    "/dev/xvdci",
    "/dev/xvdcj",
    "/dev/xvdck",
    "/dev/xvdcl",
    "/dev/xvdcm",
    "/dev/xvdcn",
    "/dev/xvdco",
    "/dev/xvdcp",
    "/dev/xvdcq",
    "/dev/xvdcr",
    "/dev/xvdcs",
    "/dev/xvdct",
    "/dev/xvdcu",
    "/dev/xvdcv",
    "/dev/xvdcw",
    "/dev/xvdcx",
    "/dev/xvdda",
    "/dev/xvddb",
    "/dev/xvddc",
    "/dev/xvddd",
    "/dev/xvdde",
    "/dev/xvddf",
    "/dev/xvddg",
    "/dev/xvddh",
    "/dev/xvddi",
    "/dev/xvddj",
    "/dev/xvddk",
    "/dev/xvddl",
    "/dev/xvddm",
    "/dev/xvddn",
    "/dev/xvddo",
    "/dev/xvddp",
    "/dev/xvddq",
    "/dev/xvddr",
    "/dev/xvdds",
    "/dev/xvddt",
    "/dev/xvddu",
    "/dev/xvddv",
    "/dev/xvddw",
    "/dev/xvddx"
  ]

  # Write cache and EBS read cache tput/iops
  write_cache_tput     = var.write_cache_type == "gp2" || var.write_cache_type == "io2" ? null : (var.write_cache_tput == null ? lookup(var.ec2_map[var.instance_type], "wcacheTput") : var.write_cache_tput)
  write_cache_iops_gp3 = var.write_cache_iops == null ? lookup(var.ec2_map[var.instance_type], "wcacheIOPSgp3") : var.write_cache_iops
  write_cache_iops_io2 = var.write_cache_iops == null ? lookup(var.ec2_map[var.instance_type], "wcacheIOPSio2") : var.write_cache_iops
  write_cache_iops     = var.write_cache_type == "gp2" ? null : (var.write_cache_type == "gp3" ? local.write_cache_iops_gp3 : local.write_cache_iops_io2)

  read_cache_tput = var.write_cache_type == "gp2" || var.write_cache_type == "io2" ? null : 525
  read_cache_iops = var.write_cache_type == "gp2" ? null : 12500

  # Cluster tunables
  refill_IOPS = lookup(var.ec2_map[var.instance_type], "wcacheRefillIOPs")
  refill_Bps  = lookup(var.ec2_map[var.instance_type], "wcacheRefillBps")
  disk_count  = lookup(var.ec2_map[var.instance_type], "wcacheSlots")
  EBS_BW      = lookup(var.ec2_map[var.instance_type], "wcacheEBSBW")
  EC2_BW      = lookup(var.ec2_map[var.instance_type], "wcacheEC2BW")

  # ENA Express for supported instance types
  ena_express = var.aws_partition == "aws" ? lookup(var.ec2_map[var.instance_type], "enaExpress") : "no"

  #Write cache EBS volumes
  wcache_ebs_block_devices = [
    for i in range(lookup(var.ec2_map[var.instance_type], "wcacheSlots")) : {
      device_name = local.device_names[i]
      volume_type = var.write_cache_type
      volume_size = lookup(var.ec2_map[var.instance_type], "wcacheSize")
      volume_tput = local.write_cache_tput
      volume_iops = local.write_cache_iops
      volume_tag  = var.write_cache_type
    }
  ]

  #DKV EBS volumes.
  dkv_ebs_block_devices = [
    for i in range(lookup(var.ec2_map[var.instance_type], "dkvSlots")) : {
      device_name = local.device_names[i + lookup(var.ec2_map[var.instance_type], "wcacheSlots")]
      volume_type = var.boot_dkv_type
      volume_size = lookup(var.ec2_map[var.instance_type], "dkvSize")
      volume_tput = var.boot_dkv_type == "gp2" ? null : 125
      volume_iops = var.boot_dkv_type == "gp2" ? null : 3000
      volume_tag  = var.write_cache_type
    }
  ]

  #Read Cach EBS volumes (for non-storage optimized instance types).
  rcache_ebs_block_devices = [
    for i in range(lookup(var.ec2_map[var.instance_type], "rcacheSlots")) : {
      device_name = local.device_names[i + lookup(var.ec2_map[var.instance_type], "wcacheSlots") + i + lookup(var.ec2_map[var.instance_type], "dkvSlots")]
      volume_type = var.write_cache_type
      volume_size = 1024
      volume_tput = local.read_cache_tput
      volume_iops = local.read_cache_iops
      volume_tag  = var.write_cache_type
    }
  ]

  ebs_block_devices = concat(
    local.wcache_ebs_block_devices,
    local.dkv_ebs_block_devices,
    local.rcache_ebs_block_devices
  )

  ingress_rules = [
    {
      port        = 21
      description = "TCP port for FTP"
      protocol    = "tcp"
    },
    {
      port        = 22
      description = "TCP port for SSH"
      protocol    = "tcp"
    },
    {
      port        = 53
      description = "TCP port for DNS"
      protocol    = "tcp"
    },
    {
      port        = 53
      description = "UDP port for DNS"
      protocol    = "udp"
    },
    {
      port        = 80
      description = "TCP port for HTTP"
      protocol    = "tcp"
    },
    {
      port        = 111
      description = "TCP port for SUNRPC"
      protocol    = "tcp"
    },
    {
      port        = 443
      description = "TCP port for HTTPS"
      protocol    = "tcp"
    },
    {
      port        = 445
      description = "TCP port for SMB"
      protocol    = "tcp"
    },
    {
      port        = 2049
      description = "TCP port for NFS"
      protocol    = "tcp"
    },
    {
      port        = 3712
      description = "TCP port for Replication"
      protocol    = "tcp"
    },
    {
      port        = 3713
      description = "TCP port for GNS"
      protocol    = "tcp"
    },
    {
      port        = 8000
      description = "TCP port for REST"
      protocol    = "tcp"
    },
    {
      port        = 111
      description = "UDP port for SUNRPC"
      protocol    = "udp"
    },
    {
      port        = 9000
      description = "TCP port for S3"
      protocol    = "tcp"
    },
    {
      port        = 2049
      description = "UDP port for NFS"
      protocol    = "udp"
    }
  ]
}

# Check the capacity constraint and throw an error if a larger instance type is required
resource "null_resource" "check_capacity_constraint" {
  count = local.capacity_unconstrained ? 0 : "The number of and type of instances chosen will not support the soft_capacity_limit requested.  Increase the node count or switch to a larger instance type."
}

resource "aws_security_group" "cluster" {
  name        = "${var.deployment_unique_name}-qumulo-cluster"
  description = "Enable ports for NFS/SMB/FTP/SSH, Management, Replication, and Clustering."
  vpc_id      = var.aws_vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Qumulo Internode Communication"
    from_port   = 0
    protocol    = -1
    to_port     = 0
    self        = true
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

resource "aws_iam_role" "q_access" {
  name = "${var.deployment_unique_name}-qumulo-cluster"

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

resource "aws_iam_instance_profile" "q_access" {
  name = "${var.deployment_unique_name}-qumulo-cluster"
  role = aws_iam_role.q_access.name
}

resource "aws_iam_role_policy_attachment" "ssmrole" {
  role       = aws_iam_role.q_access.name
  policy_arn = data.aws_iam_policy.ssmrole.arn
}

resource "aws_iam_role_policy" "policy1" {
  name   = "EC2-CW-logs-policy"
  role   = aws_iam_role.q_access.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:DeleteAlarms",
        "cloudwatch:PutMetricAlarm",
        "ec2:AssignPrivateIpAddresses",
        "ec2:DescribeInstances",
        "ec2:UnassignPrivateIpAddresses",
        "kms:Decrypt",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "policy2" {
  name   = "CMK-EBS-policy"
  role   = aws_iam_role.q_access.id
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
        "kms:GenerateDataKeyWithoutPlaintext",
        "kms:ReEncryptFrom",
        "kms:ReEncryptTo"
      ],
      "Resource": "${local.kms_ebs_arn}"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "policy3" {
  name   = "CMK-S3-policy"
  role   = aws_iam_role.q_access.id
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
      "Resource": "${local.kms_s3_arn}"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "policy4" {
  name   = "S3-policy"
  role   = aws_iam_role.q_access.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",        
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": ${local.persistent_bucket_arns_json}
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "policy5" {
  name   = "S3-install-policy"
  role   = aws_iam_role.q_access.id
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
        "${local.install_s3_arn}/*",
        "${local.install_s3_arn}"
      ]
    }
  ]
}
EOF
}

resource "aws_placement_group" "cluster" {
  name     = var.deployment_unique_name
  strategy = var.aws_number_azs == 1 ? "cluster" : "spread"

  tags = merge(var.tags, { Name = "${var.deployment_unique_name}" })
}

resource "aws_network_interface" "node" {
  count = var.node_count

  private_ips_count = local.node_fips[count.index]
  security_groups   = var.cluster_additional_sg_ids == [] ? [aws_security_group.cluster.id] : concat([aws_security_group.cluster.id], var.cluster_additional_sg_ids)
  subnet_id         = var.private_subnet_ids[count.index]

  tags = merge(var.tags, { Name = "${var.deployment_unique_name}-node ${count.index + 1}" })

  lifecycle { ignore_changes = [private_ips_count, subnet_id] }
}

resource "aws_instance" "node" {
  count = var.node_count

  ami                     = local.ami_id
  disable_api_termination = var.term_protection
  ebs_optimized           = true
  instance_type           = var.instance_type
  key_name                = var.ec2_key_pair
  placement_group         = aws_placement_group.cluster.id
  iam_instance_profile    = aws_iam_instance_profile.q_access.name

  user_data = templatefile("${local.user_data_template}", {
    bucket_name       = var.s3_bucket_name
    bucket_region     = var.s3_bucket_region
    install_s3_prefix = local.install_s3_prefix
  })

  tags = merge(var.tags, { Name = "${var.deployment_unique_name}-node${count.index + 1}" }, { Qumulo-Cluster = "${var.deployment_unique_name}" })

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.node[count.index].id
  }

  root_block_device {
    encrypted   = true
    kms_key_id  = var.kms_key_id == null ? "" : "arn:${var.aws_partition}:kms:${var.aws_region}:${var.aws_account_id}:key/${var.kms_key_id}"
    volume_type = var.boot_dkv_type
    volume_size = var.boot_drive_size

    tags = merge(var.tags, { Name = "${var.deployment_unique_name}-boot" })
  }

  dynamic "ebs_block_device" {
    for_each = local.ebs_block_devices
    content {
      device_name = ebs_block_device.value.device_name
      encrypted   = true
      kms_key_id  = var.kms_key_id == null ? "" : "arn:${var.aws_partition}:kms:${var.aws_region}:${var.aws_account_id}:key/${var.kms_key_id}"
      volume_type = ebs_block_device.value.volume_type
      volume_size = ebs_block_device.value.volume_size
      throughput  = ebs_block_device.value.volume_tput
      iops        = ebs_block_device.value.volume_iops

      tags = merge(var.tags, { Name = "${var.deployment_unique_name}-${ebs_block_device.value.volume_tag}" })
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 3
    http_tokens                 = var.require_imdsv2 ? "required" : "optional"
  }

  lifecycle {
    ignore_changes = [ami, instance_type, user_data, root_block_device, ebs_block_device, network_interface, placement_group, tags]

    precondition {
      condition     = local.check_cluster_remove_nodes == false
      error_message = "q_node_count is less than the number of nodes in the cluster.  Execute a Terraform apply with q_target_node_count to reduce the cluster size OR enter the correct cluster size for q_node_count."
    }

    precondition {
      condition     = local.check_workspace_on_replace == false
      error_message = "A Cluster Replace requires a new Terraform workspace (ie new state file).  Create a new TF workspace, then execute the cluster replace."
    }
  }
}

