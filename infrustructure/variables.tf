variable "aws_profile" {
  description = "The AWS profile to create things with."
  default     = "SREAssessment.Infrustructure"
}

variable "aws_region" {
  description = "The AWS region to create things in."
  default     = "ap-southeast-2"
}

variable "az_count" {
  description = "Number of AZs to cover in a given AWS region"
  type        = number
  default     = "2"
}
