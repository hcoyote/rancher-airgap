terraform {
  required_version = ">= 1.0" 
}

variable "aws_region" {
  description = "The AWS region to deploy the infrastructure on"
  default     = "us-west-2"
  type        = string
}

variable "worker_nodes" {
  description = "Number of client hosts"
  type        = number
  default     = 0
}

variable "deployment_prefix" {
  description = "The prefix for the instance name (defaults to {random uuid}-{timestamp})"
  type        = string
  default     = ""
}

variable "distro" {
  description = "The default distribution to base the cluster on"
  default     = "ubuntu-focal"
  type        = string
}


## It is important that device names do not get duplicated on hosts, in rare circumstances the choice of nodes * volumes can result in a factor that causes duplication. Modify this field so there is not a common factor.
## Please pr a more elegant solution if you have one.
variable "ec2_ebs_device_names" {
  description = "Device names for EBS volumes"
  type        = list(string)
  default     = [
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
    "/dev/xvdby",
    "/dev/xvdbz"
  ]
}

variable "ec2_ebs_volume_count" {
  description = "Number of EBS volumes to attach to each Redpanda node"
  default     = 0
  type        = number
}

variable "ec2_ebs_volume_iops" {
  description = "IOPs for GP3 Volumes"
  default     = 16000
  type        = number
}

variable "ec2_ebs_volume_size" {
  description = "Size of each EBS volume"
  default     = 100
  type        = number
}

variable "ec2_ebs_volume_throughput" {
  description = "Throughput per volume in MiB"
  default     = 250
  type        = number
}

variable "ec2_ebs_volume_type" {
  description = "EBS Volume Type (gp3 recommended for performance)"
  default     = "gp3"
  type        = string
}

variable "instance_type" {
  description = "Default redpanda instance type to create"
  default     = "i3.2xlarge"
  type        = string
}

variable "machine_architecture" {
  description = "Architecture used for selecting the AMI - change this if using ARM based instances"
  default     = "x86_64"
  type        = string
}

variable "leader_nodes" {
  description = "The number of nodes to deploy"
  type        = number
  default     = "1"
}

variable "leader_nodes_root_size" {
  description = "Size in GB (default=100) of /dev/root for leader nodes"
  type        = number
  default     = 100
}


variable "worker_nodes_root_size" {
  description = "Size in GB (default=100) of /dev/root for worker nodes"
  type        = number
  default     = 100
}

variable "proxy_instance_type" {
  description = "Default redpanda instance type to create"
  default     = "t3a.medium"
  type        = string
}
# you probably only ever need 1
variable "proxy_nodes" {
  description = "The number of proxy nodes to deploy"
  type        = number
  default     = "1"
}

variable "cluster_ami" {
  description = "AMI for Redpanda broker nodes (if not set, will select based on the client_distro variable"
  default     = null
  type        = string
}

variable "proxy_nodes_root_size" {
  description = "Size in GB (default=100) of /dev/root for leader nodes"
  type        = number
  default     = 100
}

variable "public_key_path" {
  description = "The public key used to ssh to the hosts"
  default     = "~/.ssh/id_rsa.pub"
  type        = string
}

data "aws_ami" "ami" {
    most_recent = true

    filter {
        name   = "name"
        values = ["ubuntu/images/hvm-ssd/ubuntu-*-amd64-server-*", "Fedora-Cloud-Base-*.x86_64-hvm-us-west-2-gp2-0", "debian-*-amd64-*", "debian-*-hvm-x86_64-gp2-*'", "amzn2-ami-hvm-2.0.*-x86_64-gp2", "RHEL*HVM-*-x86_64*Hourly2-GP2"]
    }

    filter {
        name  = "architecture"
        values = [var.machine_architecture]
    }

    filter {
        name = "name"
        values = ["*${var.distro}*"]
    }

    filter {
        name   = "virtualization-type"
        values = ["hvm"]
    }

    owners = ["099720109477", "125523088429", "136693071363", "137112412989", "309956199498"] # Canonical, Fedora, Debian (new), Amazon, RedHat
}

variable "distro_ssh_user" {
  description = "The default user used by the AWS AMIs"
  type        = map(string)
  default     = {
    "debian-10"            = "admin"
    "debian-11"            = "admin"
    "Fedora-Cloud-Base-34" = "fedora"
    "Fedora-Cloud-Base-35" = "fedora"
    #"Fedora-Cloud-Base-36" = "fedora"
    #"Fedora-Cloud-Base-37" = "fedora"
    "ubuntu-bionic"        = "ubuntu"
    "ubuntu-focal"         = "ubuntu"
    "ubuntu-hirsute"       = "ubuntu"
    "ubuntu-jammy"         = "ubuntu"
    "ubuntu-kinetic"       = "ubuntu"
    "RHEL-8"               = "ec2-user"
    #"RHEL-9"              = "ec2-user"
    "amzn2"                = "ec2-user"
  }
}

variable "ubuntu_cidrs" {
	type = list
	default = [
	"54.191.70.203/32",
	"34.212.136.213/32",
	"54.218.137.160/32",
	"54.190.18.91/32",
	"54.191.55.41/32",
	"34.210.25.51/32",
	"185.125.190.39/32",
	"91.189.91.39/32",
	"185.125.190.36/32",
	]
}
