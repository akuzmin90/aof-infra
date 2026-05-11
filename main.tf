resource "aws_s3_bucket" "test" {
  bucket = "hitmakers-test"
}

resource "aws_s3_object" "test" {
  bucket  = aws_s3_bucket.test.id
  key     = "test.txt"
  content = "Test text here"
}
