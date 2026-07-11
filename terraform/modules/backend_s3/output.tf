output "bucket_name" {
  value = aws_s3_bucket.backend.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.backend.arn
}