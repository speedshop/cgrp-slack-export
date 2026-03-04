provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

resource "cloudflare_r2_bucket" "railsperf_exports" {
  account_id = var.cloudflare_account_id
  name       = var.r2_bucket_name
}
