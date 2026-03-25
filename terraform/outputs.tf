output "r2_bucket_name" {
  description = "Managed R2 bucket name."
  value       = cloudflare_r2_bucket.railsperf_exports.name
}

output "r2_s3_endpoint" {
  description = "S3-compatible endpoint for this Cloudflare account."
  value       = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"
}

output "r2_object_key" {
  description = "Default key to upload from mise run upload."
  value       = var.r2_object_key
}
