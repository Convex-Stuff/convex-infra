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

variable "TAILNET_IP" {
  type        = string
  description = "GitHub repo variable: TAILNET_IP. jackserver's Tailscale address. Remote telemetry ingestion ports bind to this interface only, so they are reachable from the tailnet and nowhere else."

  # An unset GitHub variable arrives as an empty string, which would satisfy a
  # bare required-variable check and then make docker publish on every
  # interface. Require an address in Tailscale's 100.64.0.0/10 range instead.
  validation {
    condition     = can(regex("^100\\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\\.[0-9]{1,3}\\.[0-9]{1,3}$", var.TAILNET_IP))
    error_message = "TAILNET_IP must be jackserver's Tailscale address in 100.64.0.0/10, e.g. 100.101.102.103. Run 'tailscale ip -4' on jackserver."
  }
}
