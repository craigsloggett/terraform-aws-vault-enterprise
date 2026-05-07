check "ebs_within_instance_baseline" {
  assert {
    condition = var.compute.raft_data_disk.iops <= try(
      local.ebs_baseline[var.compute.instance_type].iops,
      var.compute.raft_data_disk.iops,
    )
    error_message = format(
      "raft_data_disk provisioned IOPS (%d) exceeds %s baseline (%d). The instance will throttle to baseline after the 30-minute daily burst credit exhausts.",
      var.compute.raft_data_disk.iops,
      var.compute.instance_type,
      try(local.ebs_baseline[var.compute.instance_type].iops, 0),
    )
  }

  assert {
    condition = var.compute.raft_data_disk.throughput <= try(
      local.ebs_baseline[var.compute.instance_type].throughput,
      var.compute.raft_data_disk.throughput,
    )
    error_message = format(
      "raft_data_disk provisioned throughput (%d MiB/s) exceeds %s baseline (%d MiB/s). The instance will throttle to baseline after the 30-minute daily burst credit exhausts.",
      var.compute.raft_data_disk.throughput,
      var.compute.instance_type,
      try(local.ebs_baseline[var.compute.instance_type].throughput, 0),
    )
  }

  assert {
    condition = var.compute.audit_disk.iops <= try(
      local.ebs_baseline[var.compute.instance_type].iops,
      var.compute.audit_disk.iops,
    )
    error_message = format(
      "audit_disk provisioned IOPS (%d) exceeds %s baseline (%d). The instance will throttle to baseline after the 30-minute daily burst credit exhausts.",
      var.compute.audit_disk.iops,
      var.compute.instance_type,
      try(local.ebs_baseline[var.compute.instance_type].iops, 0),
    )
  }

  assert {
    condition = var.compute.audit_disk.throughput <= try(
      local.ebs_baseline[var.compute.instance_type].throughput,
      var.compute.audit_disk.throughput,
    )
    error_message = format(
      "audit_disk provisioned throughput (%d MiB/s) exceeds %s baseline (%d MiB/s). The instance will throttle to baseline after the 30-minute daily burst credit exhausts.",
      var.compute.audit_disk.throughput,
      var.compute.instance_type,
      try(local.ebs_baseline[var.compute.instance_type].throughput, 0),
    )
  }
}
