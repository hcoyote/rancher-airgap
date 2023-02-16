terraform {
  required_version = ">= 1.0" 
}

resource "random_uuid" "cluster" {}

resource "time_static" "timestamp" {}

locals {
  uuid                       = random_uuid.cluster.result
  timestamp                  = time_static.timestamp.unix
  deployment_id              = length(var.deployment_prefix) > 0 ? var.deployment_prefix : "redpanda-${substr(local.uuid, 0, 8)}-${local.timestamp}"

  # tags shared by all instances
  instance_tags = {
    owner        : local.deployment_id
    iam_username : trimprefix(data.aws_arn.caller_arn.resource, "user/")
  }
}

#
# AWS Networking wire up for Rancher VPC
#
# TF Names:
# 
# rancher_vpc -> rancher_subnet -> rancher_rt -> rancher_igw -> 0.0.0.0 
# 10.0.0.0/16    10.0.0.0/24       routes for    
#                                  0.0.0.0
#                                  10.0.0.0/160
#
# vpc builds a subnet with a route table to allow packets to the world via 
# the internet gateway.
#
# Note: we set the vpc's main route table association to rancher_rt to
# prevent a stray route table from automatically being generated and
# stopping traffic from routing correctly.
#
# VPC Name tags (for easier understanding in AWS UI)
#
#     rancher-airgap-<random> (vpc)
#     rancher-airgap-subnet-<random>
#     rancher-airgap-rt-<random>
#     rancher-airgap-igw-<random>
#
resource "aws_vpc" "rancher_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "rancher-airgap-${substr(local.uuid, 0, 8)}"
  }
}

resource "aws_subnet" "rancher_subnet" {
  vpc_id     = aws_vpc.rancher_vpc.id
  cidr_block = "10.0.0.0/24"
  tags = {
    Name = "rancher-airgap-subnet-${substr(local.uuid, 0, 8)}"
  }
}

resource "aws_internet_gateway" "rancher_igw" {
  vpc_id     = aws_vpc.rancher_vpc.id
  tags = {
    Name = "rancher-airgap-igw-${substr(local.uuid, 0, 8)}"
  }
}

resource "aws_route_table" "rancher_rt" {
  vpc_id     = aws_vpc.rancher_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.rancher_igw.id
  }

  tags = {
    Name = "rancher-airgap-rt-${substr(local.uuid, 0, 8)}"
  }
}

resource "aws_main_route_table_association" "rancher_mrta" {
  vpc_id = aws_vpc.rancher_vpc.id
  route_table_id = aws_route_table.rancher_rt.id
}

#
# AWS Instance definitions
#
#
resource "aws_instance" "leader" {
  count                      = var.leader_nodes
  ami                        = coalesce(var.cluster_ami, data.aws_ami.ami.image_id)
  instance_type              = var.instance_type
  key_name                   = aws_key_pair.ssh.key_name
  vpc_security_group_ids     = [aws_security_group.node_sec_group.id]
  associate_public_ip_address = true
  subnet_id                  = aws_subnet.rancher_subnet.id
  tags                       = merge(
    local.instance_tags,
    {
      Name = "${local.deployment_id}-leader-node-${count.index}",
      Nodetype = "rancher-rke2-leader"
    }
  )

  root_block_device {
    volume_size = var.leader_nodes_root_size
  }
  connection {
    user        = var.distro_ssh_user[var.distro]
    host        = self.public_ip
    private_key = file(var.private_key_path)
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_instance" "worker" {
  count                      = var.worker_nodes
  ami                        = coalesce(var.cluster_ami, data.aws_ami.ami.image_id)
  instance_type              = var.instance_type
  key_name                   = aws_key_pair.ssh.key_name
  vpc_security_group_ids     = [aws_security_group.node_sec_group.id]
  associate_public_ip_address = true
  subnet_id                  = aws_subnet.rancher_subnet.id
  tags                       = merge(
    local.instance_tags,
    {
      Name = "${local.deployment_id}-worker-node-${count.index}",
      Nodetype = "rancher-rke2-worker"
    }
  )

  root_block_device {
    volume_size = var.worker_nodes_root_size
  }
  connection {
    user        = var.distro_ssh_user[var.distro]
    host        = self.public_ip
    private_key = file(var.private_key_path)
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_instance" "proxy" {
  count                      = var.proxy_nodes
  ami                        = coalesce(var.cluster_ami, data.aws_ami.ami.image_id)
  instance_type              = var.proxy_instance_type
  key_name                   = aws_key_pair.ssh.key_name
  vpc_security_group_ids     = [aws_security_group.proxy_sec_group.id]
  associate_public_ip_address = true
  subnet_id                  = aws_subnet.rancher_subnet.id
  tags                       = merge(
    local.instance_tags,
    {
      Name = "${local.deployment_id}-proxy-node-${count.index}",
      nodetype = "proxy"
    }
  )

  root_block_device {
    volume_size = var.proxy_nodes_root_size
  }
  connection {
    user        = var.distro_ssh_user[var.distro]
    host        = self.public_ip
    private_key = file(var.private_key_path)
  }

  lifecycle {
    ignore_changes = [ami]
  }
}



resource "aws_ebs_volume" "ebs_volume" {
  count             = var.leader_nodes * var.ec2_ebs_volume_count
  availability_zone = element(aws_instance.leader[*].availability_zone, count.index)
  size              = var.ec2_ebs_volume_size
  type              = var.ec2_ebs_volume_type
  iops              = var.ec2_ebs_volume_iops
  throughput        = var.ec2_ebs_volume_throughput
}

resource "aws_volume_attachment" "volume_attachment" {
  count       = var.leader_nodes * var.ec2_ebs_volume_count
  volume_id   = aws_ebs_volume.ebs_volume[*].id[count.index]
  device_name = element(var.ec2_ebs_device_names, count.index)
  instance_id = element(aws_instance.leader[*].id, count.index)
}


#
# Security Group: Proxy controls
#
#
#
resource "aws_security_group" "proxy_sec_group" {
  name        = "${local.deployment_id}-proxy-sec-group"
  tags        = local.instance_tags
  description = "rancher registry proxy access"
  vpc_id      = aws_vpc.rancher_vpc.id

}

resource "aws_security_group_rule" "proxy_sec_group_ssh_inbound" {
  type              = "ingress"
  description       = "PROXY: allow ssh to any in security group"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.proxy_sec_group.id
}

resource "aws_security_group_rule" "proxy_sec_group_intra_inbound" {
  type              = "ingress"
  description       = "PROXY: allow to anything from anything within the security group"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.proxy_sec_group.id
}

resource "aws_security_group_rule" "proxy_sec_group_intra_outbound" {
  type              = "egress"
  description       = "PROXY: allow from anything to anything within the security group"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.proxy_sec_group.id
}

resource "aws_security_group_rule" "proxy_sec_group_any_outbound" {
  type              = "egress"
  description       = "PROXY: allow any outbound"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.proxy_sec_group.id
}

resource "aws_security_group_rule" "proxy_sec_group_from_node_sec_group" {
  type              = "ingress"
  description       = "PROXY: allow rancher sg to talk to proxy sg"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  security_group_id = aws_security_group.proxy_sec_group.id
  source_security_group_id = aws_security_group.node_sec_group.id
}

resource "aws_security_group_rule" "proxy_sec_group_to_node_sec_group" {
  type              = "egress"
  description       = "PROXY: allow proxy sg to talk to rancher sg"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  security_group_id = aws_security_group.proxy_sec_group.id
  source_security_group_id = aws_security_group.node_sec_group.id
}


#
# Security Group: Rancher controls
#
#
#
resource "aws_security_group" "node_sec_group" {
  name        = "${local.deployment_id}-node-sec-group"
  tags        = local.instance_tags
  description = "rancher  ports"
  vpc_id      = aws_vpc.rancher_vpc.id

}

resource "aws_security_group_rule" "node_sec_group_ssh_inbound" {
  type              = "ingress"
  description       = "RANCHER: allow ssh to any in security group"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.node_sec_group.id
}

resource "aws_security_group_rule" "node_sec_group_intra_inbound" {
  type              = "ingress"
  description       = "RANCHER: allow to anything from anything within the security group"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.node_sec_group.id
}

resource "aws_security_group_rule" "node_sec_group_intra_outbound" {
  type              = "egress"
  description       = "RANCHER: allow from anything to anything within the security group"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.node_sec_group.id
}

resource "aws_security_group_rule" "node_sec_group_from_proxy_sec_group" {
  type              = "ingress"
  description       = "RANCHER: allow proxy sg to talk to rancher sg"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  security_group_id = aws_security_group.node_sec_group.id
  source_security_group_id = aws_security_group.proxy_sec_group.id
}

resource "aws_security_group_rule" "node_sec_group_to_proxy_sec_group" {
  type              = "egress"
  description       = "PROXY: allow proxy sg to talk to rancher sg"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  security_group_id = aws_security_group.node_sec_group.id
  source_security_group_id = aws_security_group.proxy_sec_group.id
}


resource "aws_security_group_rule" "node_sec_group_rancherapi_inbound" {
  type              = "ingress"
  description       = "RANCHER: allow any to rancher api in security group"
  from_port         = 6443
  to_port           = 6443 
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.node_sec_group.id
}


resource "aws_security_group_rule" "node_sec_group_rancherui_inbound" {
  type              = "ingress"
  description       = "RANCHER: allow any to rancher management in security group"
  from_port         = 443
  to_port           = 443 
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.node_sec_group.id
}

#resource "aws_security_group_rule" "node_sec_group_rancherweb_outbound" {
#  type              = "egress"
#  description       = "RANCHER: allow any to rancher management in security group"
#  from_port         = 443
#  to_port           = 443 
#  protocol          = "tcp"
#  cidr_blocks = [
#      "13.33.252.31/32", # rancher.com
#      "13.33.252.27/32", # rancher.com
#      "13.33.252.49/32", # rancher.com
#      "13.33.252.45/32", # rancher.com
#      "152.195.19.97/32", # get.helm.sh
#      "104.21.42.101/32", # rke2.io
#      "172.67.204.246/32" # rke2.io
#    ]
#  security_group_id = aws_security_group.node_sec_group.id
#}
#resource "aws_security_group_rule" "node_sec_group_ubuntuhttps_outbound" {
#  type              = "egress"
#  description       = "RANCHER: allow outbound to ubuntu mirrors"
#  from_port         = 443
#  to_port           = 443 
#  protocol          = "tcp"
#  cidr_blocks       = var.ubuntu_cidrs
#  security_group_id = aws_security_group.node_sec_group.id
#}
#resource "aws_security_group_rule" "node_sec_group_ubuntuhttp_outbound" {
#  type              = "egress"
#  description       = "RANCHER: allow outbound to ubuntu mirrors"
#  from_port         = 80
#  to_port           = 80 
#  protocol          = "tcp"
#  cidr_blocks       = var.ubuntu_cidrs
#  security_group_id = aws_security_group.node_sec_group.id
#}
#resource "aws_security_group_rule" "node_sec_group_github_outbound" {
#  type              = "egress"
#  description       = "RANCHER: allow outbound to github"
#  from_port         = 80
#  to_port           = 80 
#  protocol          = "tcp"
#  cidr_blocks = [    
#     "192.30.252.0/22",
#    "185.199.108.0/22",
#    "140.82.112.0/20",
#    "143.55.64.0/20",
#    "20.201.28.151/32",
#    "20.205.243.166/32",
#    "102.133.202.242/32",
#    "20.248.137.48/32",
#    "20.207.73.82/32",
#    "20.27.177.113/32",
#    "20.200.245.247/32",
#    "20.233.54.53/32"]
#
#  security_group_id = aws_security_group.node_sec_group.id
#}



  #egress {
  #  description = "allow outbound to docker registry"
  #  from_port   = 443
  #  to_port     = 443
  #  protocol    = "tcp"
  #  cidr_blocks = ["44.196.175.70/32",
  #    "52.3.144.121/32",
  #    "54.165.156.197/32",
  #    # registry-1.docker.io
  #    "52.1.184.176/32",
  #    "34.194.164.123/32",
  #    "18.215.138.58/32",
  #    # production.cloudflare.docker.com
  #    "104.18.124.25/32",
  #    "104.18.123.25/32",
  #    "104.18.122.25/32",
  #    "104.18.121.25/32",
  #    "104.18.125.25/32",
  #  ]
  #}

resource "aws_key_pair" "ssh" {
  key_name   = "${local.deployment_id}-key"
  public_key = file(var.public_key_path)
  tags       = local.instance_tags
}

resource "local_file" "hosts_ini" {
  content = templatefile("${path.module}/../templates/hosts_ini.tpl",
    {
      worker_public_ips          = aws_instance.worker[*].public_ip
      worker_private_ips         = aws_instance.worker[*].private_ip
      leader_public_ips          = aws_instance.leader[*].public_ip
      leader_private_ips         = aws_instance.leader[*].private_ip
      proxy_public_ips          = aws_instance.proxy[*].public_ip
      proxy_private_ips         = aws_instance.proxy[*].private_ip
  
  
      ssh_user                   = var.distro_ssh_user[var.distro]
    }
  )
  filename = "${path.module}/../hosts.ini"
}

# we extract the IAM username by getting the caller identity as an ARN
# then extracting the resource protion, which gives something like 
# user/travis.downs, and finally we strip the user/ part to use as a tag
data "aws_caller_identity" "current" {}

data "aws_arn" "caller_arn" {
  arn = data.aws_caller_identity.current.arn
}
