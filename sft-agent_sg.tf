resource "aws_security_group" "sft_agent_service" {
  name        = "sft_agent_service"
  description = "Control access to and from data egress service"
  vpc_id      = data.terraform_remote_state.aws_sdx.outputs.vpc.vpc.id

  tags = merge(
    local.common_tags,
    {
      Name = "sft_agent_service"
    }
  )
}

resource "aws_security_group_rule" "sft_agent_service_s3_https" {
  description       = "Access to S3 https"
  type              = "egress"
  prefix_list_ids   = [data.terraform_remote_state.aws_sdx.outputs.vpc.prefix_list_ids.s3]
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  security_group_id = aws_security_group.sft_agent_service.id
}

resource "aws_security_group_rule" "sft_agent_service_s3_http" {
  description       = "Access to S3 http"
  type              = "egress"
  prefix_list_ids   = [data.terraform_remote_state.aws_sdx.outputs.vpc.prefix_list_ids.s3]
  protocol          = "tcp"
  from_port         = 80
  to_port           = 80
  security_group_id = aws_security_group.sft_agent_service.id
}

resource "aws_security_group_rule" "sft_agent_service_to_sdx" {
  description       = "Allow SFT agent to access SDX VIP for Crown Data Transfers"
  type              = "egress"
  protocol          = "tcp"
  from_port         = var.sft_agent_port
  to_port           = var.sft_agent_port
  security_group_id = aws_security_group.sft_agent_service.id
  cidr_blocks       = ["${data.terraform_remote_state.aws_sdx.outputs.sdx_f5_endpoint_1_vip}/32"]
}

resource "aws_security_group_rule" "sft_agent_service_to_aws_aft_hub" {
  description       = "Allow SFT agent to access AWS SFT Hub"
  type              = "egress"
  protocol          = "tcp"
  from_port         = var.sft_agent_port
  to_port           = var.sft_agent_port
  security_group_id = aws_security_group.sft_agent_service.id
  cidr_blocks       = ["${local.data_egress[local.environment].aws_hub_cidr}"]
}

#Stub nifi routes
resource "aws_security_group_rule" "snapshot_sender_egress_to_stub_nifi_lb" {
  count                    = local.use_stub_nifi[local.environment] ? 1 : 0
  description              = "Allow outbound requests to stub Nifi load balancer"
  type                     = "egress"
  from_port                = var.sft_agent_port
  to_port                  = var.sft_agent_port
  protocol                 = "tcp"
  source_security_group_id = data.terraform_remote_state.snapshot_sender.outputs.stub_nifi_lb_sg_id
  security_group_id        = aws_security_group.sft_agent_service.id
}

resource "aws_security_group_rule" "stub_nifi_lb_from_sft" {
  count                    = local.use_stub_nifi[local.environment] ? 1 : 0
  description              = "Allow ingress from Sft"
  type                     = "ingress"
  from_port                = var.sft_agent_port
  to_port                  = var.sft_agent_port
  protocol                 = "tcp"
  security_group_id        = data.terraform_remote_state.snapshot_sender.outputs.stub_nifi_lb_sg_id
  source_security_group_id = aws_security_group.sft_agent_service.id
}
