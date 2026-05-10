check "ebs_within_instance_baseline" {
  assert {
    condition = var.compute.root_disk.iops <= local.ebs_baseline_iops
    error_message = format(
      "compute.root_disk.iops (%d) exceeds the %s sustained EBS IOPS baseline (%d).",
      var.compute.root_disk.iops,
      var.compute.instance_type,
      local.ebs_baseline_iops,
    )
  }

  assert {
    condition = var.compute.root_disk.throughput <= local.ebs_baseline_throughput
    error_message = format(
      "compute.root_disk.throughput (%d MB/s) exceeds the %s sustained EBS throughput baseline (%d MB/s).",
      var.compute.root_disk.throughput,
      var.compute.instance_type,
      local.ebs_baseline_throughput,
    )
  }

  assert {
    condition = var.compute.raft_data_disk.iops <= local.ebs_baseline_iops
    error_message = format(
      "compute.raft_data_disk.iops (%d) exceeds the %s sustained EBS IOPS baseline (%d).",
      var.compute.raft_data_disk.iops,
      var.compute.instance_type,
      local.ebs_baseline_iops,
    )
  }

  assert {
    condition = var.compute.raft_data_disk.throughput <= local.ebs_baseline_throughput
    error_message = format(
      "compute.raft_data_disk.throughput (%d MB/s) exceeds the %s sustained EBS throughput baseline (%d MB/s).",
      var.compute.raft_data_disk.throughput,
      var.compute.instance_type,
      local.ebs_baseline_throughput,
    )
  }

  assert {
    condition = var.compute.audit_disk.iops <= local.ebs_baseline_iops
    error_message = format(
      "compute.audit_disk.iops (%d) exceeds the %s sustained EBS IOPS baseline (%d).",
      var.compute.audit_disk.iops,
      var.compute.instance_type,
      local.ebs_baseline_iops,
    )
  }

  assert {
    condition = var.compute.audit_disk.throughput <= local.ebs_baseline_throughput
    error_message = format(
      "compute.audit_disk.throughput (%d MB/s) exceeds the %s sustained EBS throughput baseline (%d MB/s).",
      var.compute.audit_disk.throughput,
      var.compute.instance_type,
      local.ebs_baseline_throughput,
    )
  }
}
