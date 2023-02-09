resource "random_uuid" "cluster" {}

resource "time_static" "timestamp" {}

locals {
  uuid                       = random_uuid.cluster.result
  timestamp                  = time_static.timestamp.unix
  deployment_id              = length(var.deployment_prefix) > 0 ? var.deployment_prefix : "redpanda-${substr(local.uuid, 0, 8)}-${local.timestamp}"
  tiered_storage_bucket_name = "${local.deployment_id}-bucket"

  # tags shared by all instances
  instance_tags = {
    owner        : local.deployment_id
    iam_username : trimprefix(data.aws_arn.caller_arn.resource, "user/")
  }
}

resource "aws_instance" "leader" {
  count                      = var.leader_nodes
  ami                        = coalesce(var.cluster_ami, data.aws_ami.ami.image_id)
  instance_type              = var.instance_type
  key_name                   = aws_key_pair.ssh.key_name
  vpc_security_group_ids     = [aws_security_group.node_sec_group.id]
  tags                       = merge(
    local.instance_tags,
    {
      Name = "${local.deployment_id}-node-${count.index}",
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
  tags                       = merge(
    local.instance_tags,
    {
      Name = "${local.deployment_id}-node-${count.index}",
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


resource "aws_ebs_volume" "ebs_volume" {
  count             = "${var.leader_nodes * var.ec2_ebs_volume_count}"
  availability_zone = "${element(aws_instance.leader.*.availability_zone, count.index)}"
  size              = "${var.ec2_ebs_volume_size}"
  type              = "${var.ec2_ebs_volume_type}"
  iops              = "${var.ec2_ebs_volume_iops}"
  throughput        = "${var.ec2_ebs_volume_throughput}"
}

resource "aws_volume_attachment" "volume_attachment" {
  count       = "${var.leader_nodes * var.ec2_ebs_volume_count}"
  volume_id   = "${aws_ebs_volume.ebs_volume.*.id[count.index]}"
  device_name = "${element(var.ec2_ebs_device_names, count.index)}"
  instance_id = "${element(aws_instance.leader.*.id, count.index)}"
}

resource "aws_security_group" "node_sec_group" {
  name        = "${local.deployment_id}-node-sec-group"
  tags        = local.instance_tags
  description = "rancher  ports"

  # SSH access from anywhere
  ingress {
    description = "Allow anywhere inbound to ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access from anywhere to port 6443
  ingress {
    description = "rancher api"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  
  # HTTP access from anywhere to port 6443
  ingress {
    description = "rancher manager ui"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # from anything to anything within the security group
  ingress {
    description = "from anything to anything within the security group"
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # outbound internet access
  egress {
    description = "disallow any outbound connections"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = []
  }

  # from anything to anything within the security group
  egress {
    description = "from anything to anything within the security group"
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    description = "allow outbound to get.helm.sh"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["152.195.19.97/32"]
  }

  egress {
    description = "allow outbound to ubuntu mirror repos"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.ubuntu_cidrs
  }
  egress {
    description = "allow outbound to ubuntu mirror repos"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.ubuntu_cidrs
  }



  egress {
    description = "allow outbound to docker registry"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["44.196.175.70/32",
      "52.3.144.121/32",
      "54.165.156.197/32",
      # registry-1.docker.io
      "52.1.184.176/32",
      "34.194.164.123/32",
      "18.215.138.58/32",
      # production.cloudflare.docker.com
      "104.18.124.25/32",
      "104.18.123.25/32",
      "104.18.122.25/32",
      "104.18.121.25/32",
      "104.18.125.25/32",
    ]
  }

  egress {
    description = "allow explicit https to github.com"
    from_port   = 443 
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [    "192.30.252.0/22",
    "185.199.108.0/22",
    "140.82.112.0/20",
    "143.55.64.0/20",
    "20.201.28.151/32",
    "20.205.243.166/32",
    "102.133.202.242/32",
    "20.248.137.48/32",
    "20.207.73.82/32",
    "20.27.177.113/32",
    "20.200.245.247/32",
    "20.233.54.53/32"]

  }

  egress {
    description = "allow explicit https to rke2.io for installs"
    from_port   = 443 
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["104.21.42.101/32","172.67.204.246/32"]
  }
}

resource "aws_key_pair" "ssh" {
  key_name   = "${local.deployment_id}-key"
  public_key = file(var.public_key_path)
  tags       = local.instance_tags
}

resource "local_file" "hosts_ini" {
  content = templatefile("${path.module}/../templates/hosts_ini.tpl",
    {
      worker_public_ips          = aws_instance.worker.*.public_ip
      worker_private_ips         = aws_instance.worker.*.private_ip
      leader_public_ips          = aws_instance.leader.*.public_ip
      leader_private_ips         = aws_instance.leader.*.private_ip
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
