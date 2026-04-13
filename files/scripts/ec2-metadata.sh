# shellcheck shell=sh disable=SC2154
# ec2-metadata.sh — EC2 Instance Metadata Service (IMDSv2) helpers.
#
# Requires globals: imds_endpoint, imds_token_ttl

imds_token() {
  curl -s -X PUT \
    -H "X-aws-ec2-metadata-token-ttl-seconds: ${imds_token_ttl}" \
    "${imds_endpoint}/latest/api/token"
}

imds_get() {
  path="${1}"
  token="${2}"
  curl -s -H "X-aws-ec2-metadata-token: ${token}" \
    "${imds_endpoint}/latest/meta-data/${path}"
}

get_private_ip() {
  token="$(imds_token)"
  imds_get "local-ipv4" "${token}"
}

get_instance_id() {
  token="$(imds_token)"
  imds_get "instance-id" "${token}"
}

get_availability_zone() {
  token="$(imds_token)"
  imds_get "placement/availability-zone" "${token}"
}
