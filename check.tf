check "ebs_within_instance_baseline" {
  assert {
    condition = var.compute.root_disk.iops <= data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops
    error_message = format(
      "compute.root_disk.iops (%d) exceeds the %s baseline EBS IOPS (%d). The instance bursts to %d IOPS for limited windows then throttles to baseline; provisioned IOPS above %d are billed but unusable at steady state. Set iops = %d to match the instance, or choose a larger instance type.",
      var.compute.root_disk.iops,
      var.compute.instance_type,
      data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops,
      data.aws_ec2_instance_type.compute.ebs_performance_maximum_iops,
      data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops,
      data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops,
    )
  }

  assert {
    condition = var.compute.root_disk.throughput <= data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput
    error_message = format(
      "compute.root_disk.throughput (%d MB/s) exceeds the %s baseline EBS throughput (%.1f MB/s). The instance bursts to %.1f MB/s for limited windows then throttles to baseline. Set throughput = %d to match the instance, or choose a larger instance type.",
      var.compute.root_disk.throughput,
      var.compute.instance_type,
      data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput,
      data.aws_ec2_instance_type.compute.ebs_performance_maximum_throughput,
      floor(data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput),
    )
  }

  assert {
    condition = var.compute.raft_data_disk.iops <= data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops
    error_message = format(
      "compute.raft_data_disk.iops (%d) exceeds the %s baseline EBS IOPS (%d). The instance bursts to %d IOPS for limited windows then throttles to baseline; provisioned IOPS above %d are billed but unusable at steady state. Set iops = %d to match the instance, or choose a larger instance type.",
      var.compute.raft_data_disk.iops,
      var.compute.instance_type,
      data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops,
      data.aws_ec2_instance_type.compute.ebs_performance_maximum_iops,
      data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops,
      data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops,
    )
  }

  assert {
    condition = var.compute.raft_data_disk.throughput <= data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput
    error_message = format(
      "compute.raft_data_disk.throughput (%d MB/s) exceeds the %s baseline EBS throughput (%.1f MB/s). The instance bursts to %.1f MB/s for limited windows then throttles to baseline. Set throughput = %d to match the instance, or choose a larger instance type.",
      var.compute.raft_data_disk.throughput,
      var.compute.instance_type,
      data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput,
      data.aws_ec2_instance_type.compute.ebs_performance_maximum_throughput,
      floor(data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput),
    )
  }

  assert {
    condition = var.compute.audit_disk.iops <= data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops
    error_message = format(
      "compute.audit_disk.iops (%d) exceeds the %s baseline EBS IOPS (%d). The instance bursts to %d IOPS for limited windows then throttles to baseline; provisioned IOPS above %d are billed but unusable at steady state. Set iops = %d to match the instance, or choose a larger instance type.",
      var.compute.audit_disk.iops,
      var.compute.instance_type,
      data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops,
      data.aws_ec2_instance_type.compute.ebs_performance_maximum_iops,
      data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops,
      data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops,
    )
  }

  assert {
    condition = var.compute.audit_disk.throughput <= data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput
    error_message = format(
      "compute.audit_disk.throughput (%d MB/s) exceeds the %s baseline EBS throughput (%.1f MB/s). The instance bursts to %.1f MB/s for limited windows then throttles to baseline. Set throughput = %d to match the instance, or choose a larger instance type.",
      var.compute.audit_disk.throughput,
      var.compute.instance_type,
      data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput,
      data.aws_ec2_instance_type.compute.ebs_performance_maximum_throughput,
      floor(data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput),
    )
  }
}
