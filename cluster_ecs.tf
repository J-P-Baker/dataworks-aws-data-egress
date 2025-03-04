resource "aws_ecs_cluster" "data_egress_cluster" {
  name               = local.cluster_name
  capacity_providers = [aws_ecs_capacity_provider.data_egress_cluster.name]

  tags = merge(
    local.tags,
    {
      Name = local.data_egress_ecs_friendly_name
    }
  )

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  lifecycle {
    ignore_changes = [
      setting,
    ]
  }
}

resource "aws_cloudwatch_log_group" "data_egress_cluster" {
  name              = local.cw_agent_log_group_name_data_egress_ecs
  retention_in_days = 180
  tags              = local.tags
}

resource "aws_ecs_capacity_provider" "data_egress_cluster" {
  name = local.data_egress_friendly_name

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.data_egress_server.arn
    managed_termination_protection = "DISABLED"

    managed_scaling {
      maximum_scaling_step_size = 1000
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
    }
  }

  lifecycle {
    ignore_changes = all
  }

  tags = merge(
    local.tags,
    {
      Name = local.data_egress_friendly_name
    }
  )
}

resource "aws_autoscaling_group" "data_egress_server" {
  name                      = local.data_egress_friendly_name
  min_size                  = local.data_egress_server_asg_min[local.environment]
  desired_capacity          = local.data_egress_server_asg_desired[local.environment]
  max_size                  = local.data_egress_server_asg_max[local.environment]
  protect_from_scale_in     = false
  health_check_grace_period = 600
  health_check_type         = "EC2"
  force_delete              = true
  vpc_zone_identifier       = data.terraform_remote_state.aws_sdx.outputs.subnet_sdx_connectivity.*.id

  launch_template {
    id      = aws_launch_template.data_egress_server.id
    version = aws_launch_template.data_egress_server.latest_version
  }

  dynamic "tag" {
    for_each = local.data_egress_server_tags_asg

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_template" "data_egress_server" {
  name          = local.data_egress_friendly_name
  image_id      = var.dw_al2_ecs_ami_id
  instance_type = var.data_egress_server_ec2_instance_type[local.environment]
  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true

    security_groups = [aws_security_group.data_egress_server.id]
    subnet_id       = data.terraform_remote_state.aws_sdx.outputs.subnet_sdx_connectivity.0.id
  }
  user_data = base64encode(templatefile("files/data_egress_cluster_userdata.tpl", {
    cluster_name  = local.cluster_name # Referencing the cluster resource causes a circular dependency
    instance_role = aws_iam_instance_profile.data_egress_server.name
    region        = data.aws_region.current.name
    folder        = "/mnt/config"
    mnt_bucket    = data.terraform_remote_state.common.outputs.config_bucket.id
    name          = local.data_egress_server_name
  }))
  instance_initiated_shutdown_behavior = "terminate"


  iam_instance_profile {
    arn = aws_iam_instance_profile.data_egress_server.arn
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = var.data_egress_server_ebs_volume_size[local.environment]
      volume_type           = var.data_egress_server_ebs_volume_type[local.environment]
      kms_key_id            = aws_kms_external_key.data_egress_ebs_cmk.arn
      delete_on_termination = true
      encrypted             = true
      iops                  = 6000
      throughput            = 1000
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    local.common_tags,
    {
      Name = local.data_egress_friendly_name
    }
  )

  tag_specifications {
    resource_type = "instance"

    tags = merge(
      local.common_tags,
      {
        Application  = "data_egress_server"
        Name         = "data_egress_server"
        Persistence  = "Ignore"
        AutoShutdown = "False"
        SSMEnabled   = local.data_egress_server_ssmenabled[local.environment]
      }
    )
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(
      local.common_tags,
      {
        Application = "data_egress_server"
        Name        = "data_egress_server"
      }
    )
  }
}
