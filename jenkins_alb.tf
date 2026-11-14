# Existing ACM certificate
data "aws_acm_certificate" "jenkins" {
  domain      = "jenkins.vibhordew.space"
  statuses    = ["ISSUED"]
  most_recent = true
}

# HTTPS access to the shared ALB
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb_sg.id
  description       = "HTTPS access to ALB"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# ALB -> private Jenkins EC2
resource "aws_vpc_security_group_egress_rule" "alb_to_jenkins" {
  security_group_id            = aws_security_group.alb_sg.id
  referenced_security_group_id = aws_security_group.jenkins_sg.id
  description                  = "ALB to Jenkins on port 8080"
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "jenkins_from_alb" {
  security_group_id            = aws_security_group.jenkins_sg.id
  referenced_security_group_id = aws_security_group.alb_sg.id
  description                  = "Jenkins HTTP from ALB only"
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

# Jenkins target group
resource "aws_lb_target_group" "jenkins" {
  name        = "${var.project_name}-${var.environment}-jenkins-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.project_vpc.id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/login"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-jenkins-tg"
  }
}

resource "aws_lb_target_group_attachment" "jenkins" {
  target_group_arn = aws_lb_target_group.jenkins.arn
  target_id        = aws_instance.jenkins.id
  port             = 8080
}

# HTTPS listener: deny requests by default
resource "aws_lb_listener" "jenkins_https" {
  load_balancer_arn = aws_lb.project_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = data.aws_acm_certificate.jenkins.arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Access denied"
      status_code  = "403"
    }
  }
}

# Allow Jenkins access only from trusted IP and hostname
resource "aws_lb_listener_rule" "jenkins_https" {
  listener_arn = aws_lb_listener.jenkins_https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
  }

  condition {
    host_header {
      values = ["jenkins.vibhordew.space"]
    }
  }

  condition {
    source_ip {
      values = ["103.198.165.136/32"]
    }
  }
}
