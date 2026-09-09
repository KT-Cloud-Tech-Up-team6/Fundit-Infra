packer {
  required_plugins {
    amazon = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

# 1. 빌드 변수 정의
variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "environment" {
  type    = string
  default = "dev"
}

# 2. 베이스 AMI (Ubuntu 22.04 LTS) 및 빌드용 임시 인스턴스 사양
source "amazon-ebs" "ubuntu_docker" {
  region        = var.aws_region
  instance_type = "t3.small" # 빌드용 임시 인스턴스 (AMI 생성 후 자동 종료/삭제됨)
  ssh_username  = "ubuntu"
  ami_name      = "fundit-dev-docker-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  # Canonical 공식 Ubuntu 22.04 LTS 최신 AMI 자동 조회
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"] # Canonical 공식 계정 ID
  }

  tags = {
    Name        = "fundit-dev-docker-ami"
    Project     = "Fundit"
    Environment = var.environment
    ManagedBy   = "packer"
    BaseAMI     = "{{ .SourceAMIName }}"
  }
}

# 3. 설치 프로비저닝 (Docker Engine + Compose v2 + AWS CLI v2)
build {
  name    = "fundit-docker-builder"
  sources = ["source.amazon-ebs.ubuntu_docker"]

  provisioner "shell" {
    inline = [
      "echo '=== [1/5] 시스템 패키지 업데이트 및 필수 도구 설치 ==='",
      "sudo apt-get update -y",
      "sudo apt-get install -y ca-certificates curl gnupg lsb-release unzip",

      "echo '=== [2/5] Docker 공식 저장소 등록 및 Docker Engine 설치 ==='",
      "sudo mkdir -m 0755 -p /etc/apt/keyrings",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "sudo apt-get update -y",
      "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",

      "echo '=== [3/5] ubuntu 사용자 docker 그룹 등록 및 서비스 활성화 ==='",
      "sudo usermod -aG docker ubuntu",
      "sudo systemctl enable docker",

      "echo '=== [4/5] AWS CLI v2 설치 ==='",
      "curl \"https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip\" -o \"awscliv2.zip\"",
      "unzip -q awscliv2.zip",
      "sudo ./aws/install",
      "rm -rf awscliv2.zip aws",

      "echo '=== [5/5] 설치 최종 버전 검증 ==='",
      "docker --version",
      "docker compose version",
      "/usr/local/bin/aws --version"
    ]
  }
}
