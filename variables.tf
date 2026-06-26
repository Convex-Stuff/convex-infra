variable "SERVER_USER" {
  type        = string
  description = "GitHub repo variable: SERVER_USER"
}

variable "SERVER_HOST" {
  type        = string
  description = "GitHub repo variable: SERVER_HOST"
}

variable "GF_SECURITY_ADMIN_USER" {
  type        = string
  description = "GitHub repo variable: GF_SECURITY_ADMIN_USER"
}

variable "GF_SECURITY_ADMIN_PASSWORD" {
  type        = string
  sensitive   = true
  description = "GitHub repo secret: GF_SECURITY_ADMIN_PASSWORD"
}
