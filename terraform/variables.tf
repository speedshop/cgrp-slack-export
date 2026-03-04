variable "cloudflare_account_id" {
  description = "Cloudflare account ID that owns the R2 bucket."
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with R2 edit permissions."
  type        = string
  sensitive   = true
}

variable "r2_bucket_name" {
  description = "Name of the R2 bucket that stores the latest merged export."
  type        = string
  default     = "railsperf-exports"
}

variable "r2_object_key" {
  description = "Object key for the published export zip."
  type        = string
  default     = "railsperf-export-latest.zip"
}
