variable "aws_region" {
  default = "us-east-1"
}

variable "project_name" {
  default = "devops-test"
}

variable "github_owner" {
  type        = string
  description = "GitHub organization/user"
}

variable "github_repo" {
  type        = string
  description = "Repository name"
}

variable "github_branch" {
  type        = string
  default     = "refs/heads/main"
  description = "Branch that can assume IAM role"
}
