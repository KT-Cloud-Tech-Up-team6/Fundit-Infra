import os
import unittest
from unittest.mock import MagicMock, patch

# 환경변수 모의 설정
os.environ["ROUTE_TABLE_A_ID"] = "rtb-0aaa1111"
os.environ["ROUTE_TABLE_C_ID"] = "rtb-0ccc2222"
os.environ["NAT_1_ENI_ID"] = "eni-nat11111"
os.environ["NAT_2_ENI_ID"] = "eni-nat22222"
os.environ["NAT_1_INSTANCE_ID"] = "i-01111111"
os.environ["NAT_2_INSTANCE_ID"] = "i-02222222"
os.environ["NAT_1_TAG_NAME"] = "fundit-dev-nat-1"
os.environ["NAT_2_TAG_NAME"] = "fundit-dev-nat-2"
os.environ["ALERT_SNS_TOPIC_ARN"] = "arn:aws:sns:ap-northeast-2:123456789012:fundit-dev-nat-failover-alerts"

import failover


class TestNatFailoverLambda(unittest.TestCase):
    def setUp(self):
        self.mock_ec2 = MagicMock()
        self.mock_sns = MagicMock()
        self.mock_asg = MagicMock()
        failover.ec2_client = self.mock_ec2
        failover.sns_client = self.mock_sns
        failover.autoscaling_client = self.mock_asg
        failover.ALERT_SNS_TOPIC_ARN = (
            "arn:aws:sns:ap-northeast-2:123456789012:fundit-dev-nat-failover-alerts"
        )
        failover.NAT_1_TAG_NAME = "fundit-dev-nat-1"
        failover.NAT_2_TAG_NAME = "fundit-dev-nat-2"
        failover.NAT_1_EIP_ALLOC_ID = "eipalloc-11111"
        failover.NAT_2_EIP_ALLOC_ID = "eipalloc-22222"

        # 기본 인스턴스 정보 모의 (InstanceIds 및 Filters 모두 지원)
        def default_describe_instances(*args, **kwargs):
            inst_id = None
            tag_name = None

            if "InstanceIds" in kwargs and kwargs["InstanceIds"]:
                inst_id = kwargs["InstanceIds"][0]
            elif "Filters" in kwargs and kwargs["Filters"]:
                for f in kwargs["Filters"]:
                    if f.get("Name") == "tag:Name" and f.get("Values"):
                        tag_name = f["Values"][0]
                        if tag_name == "fundit-dev-nat-1":
                            inst_id = "i-01111111"
                        elif tag_name == "fundit-dev-nat-2":
                            inst_id = "i-02222222"
            elif args and args[0]:
                inst_id = args[0][0]

            if inst_id == "i-01111111":
                eni_id = "eni-nat11111"
                tag_name = "fundit-dev-nat-1"
                public_ip = "54.180.1.1"
            elif inst_id == "i-02222222":
                eni_id = "eni-nat22222"
                tag_name = "fundit-dev-nat-2"
                public_ip = "54.180.2.2"
            else:
                eni_id = "eni-unknown"
                tag_name = tag_name or "some-other-instance"
                public_ip = "54.180.9.9"

            return {
                "Reservations": [
                    {
                        "Instances": [
                            {
                                "InstanceId": inst_id or "i-unknown",
                                "State": {"Name": "running"},
                                "Tags": [{"Key": "Name", "Value": tag_name}],
                                "PublicIpAddress": public_ip,
                                "NetworkInterfaces": [
                                    {
                                        "Attachment": {"DeviceIndex": 0},
                                        "NetworkInterfaceId": eni_id,
                                        "Association": {"PublicIp": public_ip},
                                    }
                                ],
                            }
                        ]
                    }
                ]
            }

        self.mock_ec2.describe_instances.side_effect = default_describe_instances

        # 기본 인스턴스 상태 모의 (정상 running + ok)
        def default_describe_instance_status(InstanceIds, IncludeAllInstances=True):
            return {
                "InstanceStatuses": [
                    {
                        "InstanceId": InstanceIds[0],
                        "InstanceState": {"Name": "running"},
                        "InstanceStatus": {"Status": "ok"},
                        "SystemStatus": {"Status": "ok"},
                    }
                ]
            }

        self.mock_ec2.describe_instance_status.side_effect = default_describe_instance_status

        # 기본 Floating ENI 상태 모의 (정상 in-use 및 attached)
        def default_describe_network_interfaces(*args, **kwargs):
            eni_ids = kwargs.get("NetworkInterfaceIds", [])
            eni_id = eni_ids[0] if eni_ids else "eni-default"
            inst_id = "i-01111111" if eni_id == "eni-nat11111" else "i-02222222"
            return {
                "NetworkInterfaces": [
                    {
                        "NetworkInterfaceId": eni_id,
                        "Status": "in-use",
                        "Attachment": {
                            "Status": "attached",
                            "InstanceId": inst_id,
                            "DeviceIndex": 1,
                        },
                    }
                ]
            }

        self.mock_floating_eni = MagicMock(side_effect=default_describe_network_interfaces)

        # EIP 확인용 primary ENI(DeviceIndex 0) 조회 모의. 인스턴스별 Association, 빈 dict면 공인 IP 없음
        self.primary_eni_association = {
            "i-01111111": {"PublicIp": "54.180.1.1", "AllocationId": "eipalloc-11111"},
            "i-02222222": {"PublicIp": "54.180.2.2", "AllocationId": "eipalloc-22222"},
            "i-new-99999": {"PublicIp": "54.180.1.1", "AllocationId": "eipalloc-11111"},
            "i-new-nat2": {"PublicIp": "54.180.2.2", "AllocationId": "eipalloc-22222"},
        }

        def describe_network_interfaces_router(*args, **kwargs):
            if "Filters" not in kwargs:
                return self.mock_floating_eni(*args, **kwargs)
            inst_id = next(
                f["Values"][0] for f in kwargs["Filters"] if f["Name"] == "attachment.instance-id"
            )
            iface = {
                "NetworkInterfaceId": f"eni-primary-{inst_id}",
                "Attachment": {"DeviceIndex": 0, "InstanceId": inst_id},
            }
            association = self.primary_eni_association.get(inst_id, {})
            if association:
                iface["Association"] = dict(association)
            return {"NetworkInterfaces": [iface]}

        self.mock_ec2.describe_network_interfaces.side_effect = describe_network_interfaces_router

        # 기본 ASG 인스턴스 상태 모의 (정상 InService)
        def default_describe_asg_instances(*args, **kwargs):
            inst_ids = kwargs.get("InstanceIds", [])
            inst_id = inst_ids[0] if inst_ids else "i-default"
            return {
                "AutoScalingInstances": [
                    {
                        "InstanceId": inst_id,
                        "LifecycleState": "InService",
                    }
                ]
            }

        self.mock_asg.describe_auto_scaling_instances.side_effect = default_describe_asg_instances

    def test_direct_invoke_alarm_failover(self):
        """1. CloudWatch Alarm 직접 호출 페이로드 파싱 및 파트너 정상 시 페일오버(Route Table A -> NAT-2) 검증"""
        event = {
            "source": "aws.cloudwatch",
            "alarmData": {
                "alarmName": "fundit-dev-nat-1-status-check",
                "state": {"value": "ALARM", "reason": "Threshold Crossed"},
                "configuration": {
                    "metrics": [
                        {
                            "metricStat": {
                                "metric": {
                                    "name": "StatusCheckFailed",
                                    "dimensions": {"InstanceId": "i-01111111"},
                                }
                            }
                        }
                    ]
                },
            },
        }

        def mock_describe_route_tables(RouteTableIds):
            rtb_id = RouteTableIds[0]
            if rtb_id == "rtb-0ccc2222":
                return {
                    "RouteTables": [
                        {
                            "Routes": [
                                {
                                    "DestinationCidrBlock": "0.0.0.0/0",
                                    "NetworkInterfaceId": "eni-nat22222",
                                }
                            ]
                        }
                    ]
                }
            elif rtb_id == "rtb-0aaa1111":
                return {
                    "RouteTables": [
                        {
                            "Routes": [
                                {
                                    "DestinationCidrBlock": "0.0.0.0/0",
                                    "NetworkInterfaceId": "eni-nat11111",
                                }
                            ]
                        }
                    ]
                }
            return {"RouteTables": []}

        self.mock_ec2.describe_route_tables.side_effect = mock_describe_route_tables

        result = failover.lambda_handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(result["result"]["status"], "UPDATED")
        self.assertEqual(result["result"]["route_table_id"], "rtb-0aaa1111")
        self.assertEqual(result["result"]["target_eni_id"], "eni-nat22222")
        self.mock_ec2.replace_route.assert_called_once_with(
            RouteTableId="rtb-0aaa1111",
            DestinationCidrBlock="0.0.0.0/0",
            NetworkInterfaceId="eni-nat22222",
        )
        print("\n✅ Test 1 (Direct Invoke ALARM -> Failover): PASSED")

    def test_direct_invoke_ok_failback(self):
        """2. CloudWatch Alarm 복구(OK) 페이로드 파싱 및 페일백(Route Table A -> NAT-1) 검증"""
        event = {
            "source": "aws.cloudwatch",
            "alarmData": {
                "alarmName": "fundit-dev-nat-1-status-check",
                "state": {"value": "OK", "reason": "Threshold Normal"},
                "configuration": {
                    "metrics": [
                        {
                            "metricStat": {
                                "metric": {
                                    "name": "StatusCheckFailed",
                                    "dimensions": {"InstanceId": "i-01111111"},
                                }
                            }
                        }
                    ]
                },
            },
        }

        self.mock_ec2.describe_route_tables.return_value = {
            "RouteTables": [
                {
                    "Routes": [
                        {
                            "DestinationCidrBlock": "0.0.0.0/0",
                            "NetworkInterfaceId": "eni-nat22222",
                        }
                    ]
                }
            ]
        }

        result = failover.lambda_handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(result["result"]["status"], "UPDATED")
        self.assertEqual(result["result"]["route_table_id"], "rtb-0aaa1111")
        self.assertEqual(result["result"]["target_eni_id"], "eni-nat11111")
        self.mock_ec2.replace_route.assert_called_once_with(
            RouteTableId="rtb-0aaa1111",
            DestinationCidrBlock="0.0.0.0/0",
            NetworkInterfaceId="eni-nat11111",
        )
        print("✅ Test 2 (Direct Invoke OK -> Failback): PASSED")

    def test_direct_invoke_ok_failback_deferred_when_eni_not_attached(self):
        """2-1. [조기 페일백 방지] 알람 OK 수신 시 Floating ENI가 아직 미부착(available) 상태이면 페일백 보류 및 라우트 유지 검증"""
        event = {
            "source": "aws.cloudwatch",
            "alarmData": {
                "alarmName": "fundit-dev-nat-1-status-check",
                "state": {"value": "OK"},
                "configuration": {
                    "metrics": [
                        {
                            "metricStat": {
                                "metric": {
                                    "dimensions": {"InstanceId": "i-01111111"}
                                }
                            }
                        }
                    ]
                },
            },
        }

        # Floating ENI가 아직 인스턴스에 붙지 않음 (user-data 부팅 초기 단계)
        self.mock_floating_eni.side_effect = None
        self.mock_floating_eni.return_value = {
            "NetworkInterfaces": [
                {
                    "NetworkInterfaceId": "eni-nat11111",
                    "Status": "available",
                    "Attachment": None,
                }
            ]
        }

        result = failover.lambda_handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(result["result"]["status"], "FAILBACK_DEFERRED")
        self.assertIn("not 'attached'", result["result"]["reason"])
        self.mock_ec2.replace_route.assert_not_called()
        print("✅ Test 2-1 (Failback Deferred when Floating ENI Not Attached): PASSED")

    def test_direct_invoke_ok_failback_deferred_when_instance_unhealthy(self):
        """2-2. [조기 페일백 방지] 알람 OK 수신 시 ENI는 붙었으나 인스턴스가 2/2 통과 전(부팅 중)이면 페일백 보류 검증"""
        event = {
            "source": "aws.cloudwatch",
            "alarmData": {
                "alarmName": "fundit-dev-nat-1-status-check",
                "state": {"value": "OK"},
                "configuration": {
                    "metrics": [
                        {
                            "metricStat": {
                                "metric": {
                                    "dimensions": {"InstanceId": "i-01111111"}
                                }
                            }
                        }
                    ]
                },
            },
        }

        # ENI는 붙었으나 인스턴스 상태가 아직 initializing
        self.mock_ec2.describe_instance_status.side_effect = None
        self.mock_ec2.describe_instance_status.return_value = {
            "InstanceStatuses": [
                {
                    "InstanceId": "i-01111111",
                    "InstanceState": {"Name": "running"},
                    "InstanceStatus": {"Status": "initializing"},
                    "SystemStatus": {"Status": "ok"},
                }
            ]
        }

        result = failover.lambda_handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(result["result"]["status"], "FAILBACK_DEFERRED")
        self.assertIn("not fully healthy yet", result["result"]["reason"])
        self.mock_ec2.replace_route.assert_not_called()
        print("✅ Test 2-2 (Failback Deferred when Attached Instance Unhealthy): PASSED")

    def test_partner_route_recovered_when_partner_healthy(self):
        """3. 상대 라우트가 NAT-1을 가리켜도 NAT-2가 실제로 healthy라면 상대 라우트 복구 후 정상 Failover 검증"""
        event = {
            "source": "aws.cloudwatch",
            "alarmData": {
                "alarmName": "fundit-dev-nat-1-status-check",
                "state": {"value": "ALARM"},
                "configuration": {
                    "metrics": [
                        {
                            "metricStat": {
                                "metric": {
                                    "dimensions": {"InstanceId": "i-01111111"}
                                }
                            }
                        }
                    ]
                },
            },
        }

        # RTB-C가 과거 failover 흔적으로 NAT-1(eni-nat11111)을 가리키고 있음
        def mock_describe_route_tables(RouteTableIds):
            return {
                "RouteTables": [
                    {
                        "Routes": [
                            {
                                "DestinationCidrBlock": "0.0.0.0/0",
                                "NetworkInterfaceId": "eni-nat11111",
                            }
                        ]
                    }
                ]
            }

        self.mock_ec2.describe_route_tables.side_effect = mock_describe_route_tables

        # 상대 NAT-2는 실제로 healthy한 상태임!
        result = failover.lambda_handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        # 상대 Route Table C 복구 + 내 Route Table A failover 둘 다 호출됨
        self.mock_ec2.replace_route.assert_any_call(
            RouteTableId="rtb-0ccc2222",
            DestinationCidrBlock="0.0.0.0/0",
            NetworkInterfaceId="eni-nat22222",
        )
        self.mock_ec2.replace_route.assert_any_call(
            RouteTableId="rtb-0aaa1111",
            DestinationCidrBlock="0.0.0.0/0",
            NetworkInterfaceId="eni-nat22222",
        )
        print("✅ Test 3 (Partner Route Recovered & Failover when Partner Healthy): PASSED")

    def test_concurrent_dual_failure_race_condition(self):
        """4. [동시 장애 레이스 컨디션] 파트너가 실제로 unhealthy(impaired)일 때만 DUAL_FAILURE_ABORTED 검증"""
        event = {
            "source": "aws.cloudwatch",
            "alarmData": {
                "alarmName": "fundit-dev-nat-1-status-check",
                "state": {"value": "ALARM"},
                "configuration": {
                    "metrics": [
                        {
                            "metricStat": {
                                "metric": {
                                    "dimensions": {"InstanceId": "i-01111111"}
                                }
                            }
                        }
                    ]
                },
            },
        }

        self.mock_ec2.describe_route_tables.return_value = {
            "RouteTables": [
                {
                    "Routes": [
                        {
                            "DestinationCidrBlock": "0.0.0.0/0",
                            "NetworkInterfaceId": "eni-nat22222",
                        }
                    ]
                }
            ]
        }

        # 파트너 NAT-2의 실제 EC2 상태가 impaired(장애) 상태임
        self.mock_ec2.describe_instance_status.side_effect = None
        self.mock_ec2.describe_instance_status.return_value = {
            "InstanceStatuses": [
                {
                    "InstanceId": "i-02222222",
                    "InstanceState": {"Name": "running"},
                    "InstanceStatus": {"Status": "impaired"},
                    "SystemStatus": {"Status": "ok"},
                }
            ]
        }

        result = failover.lambda_handler(event, None)

        self.assertEqual(result["statusCode"], 500)
        self.assertEqual(result["status"], "DUAL_FAILURE_ABORTED")
        self.assertIn("Partner NAT-2", result["reason"])
        self.mock_ec2.replace_route.assert_not_called()
        self.mock_sns.publish.assert_called_once()
        print("✅ Test 4 (Concurrent Dual Failure Race Condition Prevention): PASSED")

    def test_dual_failure_publishes_sns_alert(self):
        """5. DUAL_FAILURE_ABORTED 시 운영자 SNS 토픽으로 경보 발행 파라미터 검증"""
        event = {
            "source": "aws.cloudwatch",
            "alarmData": {
                "alarmName": "fundit-dev-nat-2-status-check",
                "state": {"value": "ALARM"},
                "configuration": {
                    "metrics": [
                        {
                            "metricStat": {
                                "metric": {
                                    "dimensions": {"InstanceId": "i-02222222"}
                                }
                            }
                        }
                    ]
                },
            },
        }

        self.mock_ec2.describe_instance_status.side_effect = None
        self.mock_ec2.describe_instance_status.return_value = {
            "InstanceStatuses": [
                {
                    "InstanceId": "i-01111111",
                    "InstanceState": {"Name": "stopped"},
                    "InstanceStatus": {"Status": "insufficient-data"},
                    "SystemStatus": {"Status": "insufficient-data"},
                }
            ]
        }
        self.mock_ec2.describe_route_tables.return_value = {
            "RouteTables": [
                {
                    "Routes": [
                        {
                            "DestinationCidrBlock": "0.0.0.0/0",
                            "NetworkInterfaceId": "eni-nat11111",
                        }
                    ]
                }
            ]
        }

        result = failover.lambda_handler(event, None)

        self.assertEqual(result["statusCode"], 500)
        self.assertEqual(result["status"], "DUAL_FAILURE_ABORTED")

        self.mock_sns.publish.assert_called_once()
        call_kwargs = self.mock_sns.publish.call_args[1]
        self.assertEqual(
            call_kwargs["TopicArn"],
            "arn:aws:sns:ap-northeast-2:123456789012:fundit-dev-nat-failover-alerts",
        )
        self.assertIn("Dual NAT Failure", call_kwargs["Subject"])
        print("✅ Test 5 (SNS Alert Publishing on Dual Failure): PASSED")

    def test_ec2_running_state_deferred_when_unhealthy(self):
        """6-1. [미준비 방지] EC2 running 이벤트 수신 시 아직 2/2 status check 미통과(unhealthy)이면 Reconcile 보류 검증"""
        event = {
            "source": "aws.ec2",
            "detail-type": "EC2 Instance State-change Notification",
            "detail": {
                "instance-id": "i-01111111",
                "state": "running",
            },
        }

        # 인스턴스는 running이지만 아직 초기화 중(initializing)이라 2/2 status check가 통과되지 않음
        self.mock_ec2.describe_instance_status.side_effect = None
        self.mock_ec2.describe_instance_status.return_value = {
            "InstanceStatuses": [
                {
                    "InstanceId": "i-01111111",
                    "InstanceState": {"Name": "running"},
                    "InstanceStatus": {"Status": "initializing"},
                    "SystemStatus": {"Status": "ok"},
                }
            ]
        }

        result = failover.lambda_handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(result["result"]["status"], "DEFERRED")
        self.mock_ec2.replace_route.assert_not_called()
        print("✅ Test 6-1 (Running State Reconcile Deferred when Unhealthy): PASSED")

    def test_ec2_running_state_reconciliation_by_tag(self):
        """6-2. [인스턴스 교체 대응] 새 인스턴스가 healthy 상태이면 Name 태그로 인식하여 Route Reconcile 검증"""
        event = {
            "version": "0",
            "id": "12345678-1234-1234-1234-123456789012",
            "detail-type": "EC2 Instance State-change Notification",
            "source": "aws.ec2",
            "detail": {
                "instance-id": "i-new-99999",
                "state": "running",
            },
        }

        self.mock_ec2.describe_instances.side_effect = None
        self.mock_ec2.describe_instances.return_value = {
            "Reservations": [
                {
                    "Instances": [
                        {
                            "InstanceId": "i-new-99999",
                            "Tags": [{"Key": "Name", "Value": "fundit-dev-nat-1"}],
                            "PublicIpAddress": "54.180.1.1",
                            "NetworkInterfaces": [
                                {
                                    "Attachment": {"DeviceIndex": 0},
                                    "NetworkInterfaceId": "eni-new-live-99999",
                                    "Association": {"PublicIp": "54.180.1.1"},
                                }
                            ],
                        }
                    ]
                }
            ]
        }

        self.mock_ec2.describe_route_tables.return_value = {
            "RouteTables": [
                {
                    "Routes": [
                        {
                            "DestinationCidrBlock": "0.0.0.0/0",
                            "NetworkInterfaceId": "eni-old-deleted",
                        }
                    ]
                }
            ]
        }

        self.mock_floating_eni.side_effect = None
        self.mock_floating_eni.return_value = {
            "NetworkInterfaces": [
                {
                    "NetworkInterfaceId": "eni-nat11111",
                    "Status": "in-use",
                    "Attachment": {
                        "Status": "attached",
                        "InstanceId": "i-new-99999",
                        "DeviceIndex": 1,
                    },
                }
            ]
        }


        result = failover.lambda_handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(result["result"]["status"], "RECONCILED")
        self.assertEqual(result["result"]["instance_id"], "i-new-99999")
        self.assertEqual(result["result"]["route_table_id"], "rtb-0aaa1111")
        self.assertEqual(result["result"]["eni_id"], "eni-nat11111")
        self.mock_ec2.replace_route.assert_called_once_with(
            RouteTableId="rtb-0aaa1111",
            DestinationCidrBlock="0.0.0.0/0",
            NetworkInterfaceId="eni-nat11111",
        )
        print("✅ Test 6-2 (NAT-1 Running State Reconcile with Fixed Floating ENI): PASSED")

    def test_ec2_running_state_reconciliation_nat2(self):
        """6-3. [NAT-2 복구 대응] NAT-2 running 수신 시 고정 Floating ENI(NAT_2_ENI_ID)로 RTB-C 라우팅 복구 검증"""
        event = {
            "version": "0",
            "id": "12345678-1234-1234-1234-123456789013",
            "detail-type": "EC2 Instance State-change Notification",
            "source": "aws.ec2",
            "detail": {
                "instance-id": "i-new-nat2",
                "state": "running",
            },
        }

        self.mock_ec2.describe_instances.side_effect = None
        self.mock_ec2.describe_instances.return_value = {
            "Reservations": [
                {
                    "Instances": [
                        {
                            "InstanceId": "i-new-nat2",
                            "Tags": [{"Key": "Name", "Value": "fundit-dev-nat-2"}],
                            "PublicIpAddress": "54.180.2.2",
                            "NetworkInterfaces": [
                                {
                                    "Attachment": {"DeviceIndex": 0},
                                    "NetworkInterfaceId": "eni-dynamic-live-nat2",
                                    "Association": {"PublicIp": "54.180.2.2"},
                                }
                            ],
                        }
                    ]
                }
            ]
        }

        self.mock_ec2.describe_route_tables.return_value = {
            "RouteTables": [
                {
                    "Routes": [
                        {
                            "DestinationCidrBlock": "0.0.0.0/0",
                            "NetworkInterfaceId": "eni-nat11111",  # failover 되어 있던 상태
                        }
                    ]
                }
            ]
        }

        self.mock_floating_eni.side_effect = None
        self.mock_floating_eni.return_value = {
            "NetworkInterfaces": [
                {
                    "NetworkInterfaceId": "eni-nat22222",
                    "Status": "in-use",
                    "Attachment": {
                        "Status": "attached",
                        "InstanceId": "i-new-nat2",
                        "DeviceIndex": 1,
                    },
                }
            ]
        }

        result = failover.lambda_handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(result["result"]["status"], "RECONCILED")
        self.assertEqual(result["result"]["instance_id"], "i-new-nat2")
        self.assertEqual(result["result"]["route_table_id"], "rtb-0ccc2222")
        self.assertEqual(result["result"]["eni_id"], "eni-nat22222")
        self.mock_ec2.replace_route.assert_called_once_with(
            RouteTableId="rtb-0ccc2222",
            DestinationCidrBlock="0.0.0.0/0",
            NetworkInterfaceId="eni-nat22222",
        )
        print("✅ Test 6-3 (NAT-2 Running State Reconcile with Fixed Floating ENI): PASSED")

    def test_ec2_stopped_state_fast_failover(self):
        """7. [중지 대응] NAT-1 stopped 이벤트 수신 시 즉시 RTB-A -> NAT-2로 빠른 Failover 트리거 검증"""
        event = {
            "source": "aws.ec2",
            "detail-type": "EC2 Instance State-change Notification",
            "detail": {
                "instance-id": "i-01111111",
                "state": "stopped",
            },
        }

        # RTB-A는 NAT-1, RTB-C는 NAT-2를 정상적으로 바라보고 있는 상태
        def mock_describe_route_tables(RouteTableIds):
            rtb_id = RouteTableIds[0]
            eni = "eni-nat22222" if rtb_id == "rtb-0ccc2222" else "eni-nat11111"
            return {
                "RouteTables": [
                    {
                        "Routes": [
                            {
                                "DestinationCidrBlock": "0.0.0.0/0",
                                "NetworkInterfaceId": eni,
                            }
                        ]
                    }
                ]
            }

        self.mock_ec2.describe_route_tables.side_effect = mock_describe_route_tables

        result = failover.lambda_handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(result["result"]["status"], "FAILOVER_TRIGGERED")
        self.mock_ec2.replace_route.assert_called_once_with(
            RouteTableId="rtb-0aaa1111",
            DestinationCidrBlock="0.0.0.0/0",
            NetworkInterfaceId="eni-nat22222",
        )
        print("✅ Test 7 (EC2 Stopped State Fast Failover): PASSED")


    def test_ec2_ignored_for_non_nat_instance(self):
        """8. NAT 인스턴스가 아닌 다른 EC2 인스턴스의 상태 변경 이벤트는 무시(IGNORED) 검증"""
        event = {
            "source": "aws.ec2",
            "detail-type": "EC2 Instance State-change Notification",
            "detail": {
                "instance-id": "i-eks-worker-12345",
                "state": "running",
            },
        }

        self.mock_ec2.describe_instances.side_effect = None
        self.mock_ec2.describe_instances.return_value = {
            "Reservations": [
                {
                    "Instances": [
                        {
                            "InstanceId": "i-eks-worker-12345",
                            "Tags": [{"Key": "Name", "Value": "fundit-dev-eks-node"}],
                        }
                    ]
                }
            ]
        }

        result = failover.lambda_handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(result["result"]["status"], "IGNORED")
        self.assertEqual(result["result"]["reason"], "Not a managed NAT instance")
        self.mock_ec2.replace_route.assert_not_called()
        print("✅ Test 8 (Non-NAT Instance State Change Ignored): PASSED")

    def test_running_deferred_ok_deferred_then_healthy_periodic_reconcile_failback(self):
        """
        9. [PR 리뷰 검증 시나리오]
           EC2 running 이벤트 시 보류(DEFERRED) -> 알람 OK 시 보류(FAILBACK_DEFERRED) ->
           2/2 정상화 후 EventBridge 주기적 Reconciliation 수신 시 최종 페일백(RECONCILED) 검증.
        """
        # Step 1: EC2 running 이벤트 수신 - Floating ENI가 아직 미부착(available)
        def mock_eni_available(*args, **kwargs):
            return {
                "NetworkInterfaces": [
                    {
                        "NetworkInterfaceId": "eni-nat11111",
                        "Status": "available",
                        "Attachment": {"Status": "attaching"},
                    }
                ]
            }

        self.mock_floating_eni.side_effect = mock_eni_available
        event_running = {
            "source": "aws.ec2",
            "detail-type": "EC2 Instance State-change Notification",
            "detail": {"instance-id": "i-01111111", "state": "running"},
        }
        res_step1 = failover.lambda_handler(event_running, None)
        self.assertEqual(res_step1["statusCode"], 200)
        self.assertEqual(res_step1["result"]["status"], "DEFERRED")
        self.mock_ec2.replace_route.assert_not_called()
        print("  Step 1: EC2 running -> DEFERRED verified.")

        # Step 2: 알람 OK 이벤트 수신 - ENI는 붙었으나 인스턴스 2/2 검사 미통과(initializing)
        def mock_eni_attached(*args, **kwargs):
            return {
                "NetworkInterfaces": [
                    {
                        "NetworkInterfaceId": "eni-nat11111",
                        "Status": "in-use",
                        "Attachment": {
                            "Status": "attached",
                            "InstanceId": "i-01111111",
                            "DeviceIndex": 1,
                        },
                    }
                ]
            }

        def mock_status_initializing(InstanceIds, IncludeAllInstances=True):
            return {
                "InstanceStatuses": [
                    {
                        "InstanceId": InstanceIds[0],
                        "InstanceState": {"Name": "running"},
                        "InstanceStatus": {"Status": "initializing"},
                        "SystemStatus": {"Status": "ok"},
                    }
                ]
            }

        self.mock_floating_eni.side_effect = mock_eni_attached
        self.mock_ec2.describe_instance_status.side_effect = mock_status_initializing

        event_alarm_ok = {
            "source": "aws.cloudwatch",
            "alarmData": {
                "alarmName": "fundit-dev-nat-1-status-check",
                "state": {"value": "OK"},
            },
        }
        res_step2 = failover.lambda_handler(event_alarm_ok, None)
        self.assertEqual(res_step2["result"]["status"], "FAILBACK_DEFERRED")
        self.mock_ec2.replace_route.assert_not_called()
        print("  Step 2: Alarm OK -> FAILBACK_DEFERRED verified (route kept on fallback).")

        # Step 3: 인스턴스가 2/2 검사를 통과하여 완전히 정상화됨!
        def mock_status_healthy(InstanceIds, IncludeAllInstances=True):
            return {
                "InstanceStatuses": [
                    {
                        "InstanceId": InstanceIds[0],
                        "InstanceState": {"Name": "running"},
                        "InstanceStatus": {"Status": "ok"},
                        "SystemStatus": {"Status": "ok"},
                    }
                ]
            }

        self.mock_ec2.describe_instance_status.side_effect = mock_status_healthy

        # 현재 RTB-A는 우회 경로(NAT-2 ENI)를 가리키고 있음
        self.mock_ec2.describe_route_tables.return_value = {
            "RouteTables": [
                {
                    "RouteTableId": "rtb-0aaa1111",
                    "Routes": [
                        {
                            "DestinationCidrBlock": "0.0.0.0/0",
                            "NetworkInterfaceId": "eni-nat22222",  # 우회 ENI
                        }
                    ],
                }
            ]
        }

        # EventBridge 주기적 Reconciliation (Scheduled Event) 발생
        event_scheduled = {
            "source": "aws.events",
            "detail-type": "Scheduled Event",
        }
        res_step3 = failover.lambda_handler(event_scheduled, None)
        self.assertEqual(res_step3["statusCode"], 200)
        self.assertEqual(res_step3["result"]["status"], "RECONCILED")
        self.mock_ec2.replace_route.assert_called_once_with(
            RouteTableId="rtb-0aaa1111",
            DestinationCidrBlock="0.0.0.0/0",
            NetworkInterfaceId="eni-nat11111",
        )
        print("  Step 3: 2/2 Healthy -> Periodic Reconcile executed final failback (RECONCILED).")
        print("✅ Test 9 (Running -> Deferred -> Alarm OK -> Deferred -> Reconcile Failback): PASSED")

    def test_user_data_script_fail_closed_on_timeout(self):
        """
        10. [User Data 검증]
            검사 30회 안에 준비되지 않으면 CONTINUE 대신 ABANDON을 전송하고 exit 1로 비정상 종료하여
            조기 페일백 블랙홀을 원천 방지(Fail-Closed)하는지 검증
        """
        import base64
        import re

        main_tf_path = os.path.join(
            os.path.dirname(__file__), "..", "main.tf"
        )
        with open(main_tf_path, "r", encoding="utf-8") as f:
            content = f.read()

        # user_data 블록 추출
        self.assertIn("BOOTSTRAP_SUCCESS=false", content)
        self.assertIn("ABANDON", content)
        self.assertIn("CONTINUE", content)
        self.assertIn("exit 1", content)
        self.assertIn("installed by fck-nat", content)
        self.assertIn("describe-network-interfaces", content)

        # 실패 시 ABANDON 호출 및 exit 1 검증
        abandon_block = re.search(
            r'--lifecycle-action-result ABANDON.*?exit 1', content, re.DOTALL
        )
        self.assertIsNotNone(
            abandon_block,
            "User data must call complete-lifecycle-action with ABANDON and exit with code 1 on timeout",
        )

        # 성공 시에만 CONTINUE 호출 검증
        continue_block = re.search(
            r'if \[ "\$BOOTSTRAP_SUCCESS" = "true" \]; then.*?--lifecycle-action-result CONTINUE',
            content,
            re.DOTALL,
        )
        self.assertIsNotNone(
            continue_block,
            "User data must only send CONTINUE when BOOTSTRAP_SUCCESS is true",
        )
        print("✅ Test 10 (User Data Fail-Closed and Timeout ABANDON): PASSED")

    def test_reconciliation_deferred_when_asg_pending_wait_then_reconciled_when_inservice(self):
        """
        11. [PR 리뷰 검증]
            주기적 reconciliation 시 EC2 2/2 검사를 통과했더라도
            ASG가 Pending:Wait (fck-nat/EIP 부트스트랩 미완료) 상태이면 우회 라우트를 유지(DEFERRED/NOOP)하고,
            InService 및 EIP 준비 완료 후 정상 페일백(RECONCILED)되는지 검증
        """
        # RTB-A가 현재 NAT-2 ENI(우회 경로)를 가리키고 있는 상태
        self.mock_ec2.describe_route_tables.return_value = {
            "RouteTables": [
                {
                    "RouteTableId": "rtb-0aaa1111",
                    "Routes": [
                        {
                            "DestinationCidrBlock": "0.0.0.0/0",
                            "NetworkInterfaceId": "eni-nat22222",  # 우회 ENI
                        }
                    ],
                }
            ]
        }

        # Floating ENI는 인스턴스에 정상 attached
        def mock_eni_attached(*args, **kwargs):
            return {
                "NetworkInterfaces": [
                    {
                        "NetworkInterfaceId": "eni-nat11111",
                        "Status": "in-use",
                        "Attachment": {
                            "Status": "attached",
                            "InstanceId": "i-01111111",
                            "DeviceIndex": 1,
                        },
                    }
                ]
            }
        self.mock_floating_eni.side_effect = mock_eni_attached

        # EC2 상태는 2/2 정상 통과! (running + ok + ok)
        def mock_ec2_2_2_healthy(InstanceIds, IncludeAllInstances=True):
            return {
                "InstanceStatuses": [
                    {
                        "InstanceId": "i-01111111",
                        "InstanceState": {"Name": "running"},
                        "InstanceStatus": {"Status": "ok"},
                        "SystemStatus": {"Status": "ok"},
                    }
                ]
            }
        self.mock_ec2.describe_instance_status.side_effect = mock_ec2_2_2_healthy

        # BUT 1단계: ASG Lifecycle State가 아직 Pending:Wait (부트스트랩/Hook 진행 중)
        self.mock_asg.describe_auto_scaling_instances.side_effect = None
        self.mock_asg.describe_auto_scaling_instances.return_value = {
            "AutoScalingInstances": [
                {
                    "InstanceId": "i-01111111",
                    "LifecycleState": "Pending:Wait",
                }
            ]
        }

        # EventBridge Scheduled Event (주기적 Reconciliation) 발생
        event_scheduled = {
            "source": "aws.events",
            "detail-type": "Scheduled Event",
        }
        res_pending = failover.lambda_handler(event_scheduled, None)

        # 검증 1: Pending:Wait 상태이므로 조기 페일백이 보류(DEFERRED)되고 NOOP 반환
        self.assertEqual(res_pending["statusCode"], 200)
        self.assertEqual(res_pending["result"]["status"], "NOOP")
        self.assertEqual(res_pending["result"]["details"]["route_table_a"]["status"], "DEFERRED")
        self.assertIn("Pending:Wait", res_pending["result"]["details"]["route_table_a"]["reason"])
        self.mock_ec2.replace_route.assert_not_called()
        print("  Step 1: EC2 2/2 Healthy but ASG Pending:Wait -> DEFERRED & Bypass Route Maintained.")

        # BUT 2단계: ASG InService이지만 EIP 바인딩이 아직 안 된 경우 (NAT/EIP 준비 미완료)
        self.mock_asg.describe_auto_scaling_instances.return_value = {
            "AutoScalingInstances": [
                {
                    "InstanceId": "i-01111111",
                    "LifecycleState": "InService",
                }
            ]
        }
        # primary ENI에 공인 IP·EIP가 아직 없음
        self.primary_eni_association["i-01111111"] = {}
        res_eip_missing = failover.lambda_handler(event_scheduled, None)
        self.assertEqual(res_eip_missing["result"]["status"], "NOOP")
        self.assertEqual(res_eip_missing["result"]["details"]["route_table_a"]["status"], "DEFERRED")
        self.assertIn("no public IP/EIP", res_eip_missing["result"]["details"]["route_table_a"]["reason"])
        self.mock_ec2.replace_route.assert_not_called()
        print("  Step 2: ASG InService but EIP not ready -> DEFERRED & Bypass Route Maintained.")

        # 3단계: fck-nat 완료 후 EIP 바인딩 및 ASG InService 완료!
        self.primary_eni_association["i-01111111"] = {"PublicIp": "54.180.1.1", "AllocationId": "eipalloc-11111"}

        res_inservice = failover.lambda_handler(event_scheduled, None)
        self.assertEqual(res_inservice["statusCode"], 200)
        self.assertEqual(res_inservice["result"]["status"], "RECONCILED")
        self.assertEqual(res_inservice["result"]["details"]["route_table_a"]["status"], "UPDATED")
        self.mock_ec2.replace_route.assert_called_once_with(
            RouteTableId="rtb-0aaa1111",
            DestinationCidrBlock="0.0.0.0/0",
            NetworkInterfaceId="eni-nat11111",
        )
        print("  Step 3: InService + EIP Ready -> RECONCILED (Route restored to primary Floating ENI).")
        print("✅ Test 11 (Reconciliation Deferred during ASG Pending:Wait/EIP Unready, then Reconciled): PASSED")

    def test_user_data_runtime_execution(self):
        """
        12. [User Data 런타임 서브프로세스 실행 검증]
            실제 sh 환경에서 User Data 부트스트랩 스크립트를 실행한다.
            aws mock은 실제 API에서 확인한 쿼리로 호출될 때만 값을 돌려준다.
            1) fck-nat NAT 규칙 미설치, 고정 ENI 미부착, EIP 불일치 각각에서 ABANDON 및 exit code 1인지 검증
            2) 세 조건이 모두 맞을 때 CONTINUE 및 exit code 0인지 검증
        """
        import stat
        import sys
        import tempfile
        import subprocess
        import re

        main_tf_path = os.path.join(
            os.path.dirname(__file__), "..", "main.tf"
        )
        with open(main_tf_path, "r", encoding="utf-8") as f:
            content = f.read()

        match = re.search(r"user_data = base64encode\(<<-EOF(.*?)EOF\s*\)", content, re.DOTALL)
        self.assertIsNotNone(match, "user_data block must exist in main.tf")
        raw_script = match.group(1).strip()

        # 테라폼 변수 치환. ENI와 EIP는 서로 다른 값으로 둬야 쿼리 비교가 의미를 가진다
        script = raw_script.replace("${aws_network_interface.nat[count.index].id}", "eni-floating-1")
        script = script.replace("${aws_eip.nat[count.index].id}", "eipalloc-static-1")
        script = re.sub(r"\$\{.*?\}", "mock-value", script)
        # 테스트 속도 최적화를 위해 루프 횟수 seq 1 30 -> seq 1 2, sleep 2 -> sleep 0.05
        script = script.replace("seq 1 30", "seq 1 2").replace("sleep 2", "sleep 0.05")

        with tempfile.TemporaryDirectory() as tmpdir:
            bin_dir = os.path.join(tmpdir, "bin")
            os.makedirs(bin_dir, exist_ok=True)
            log_file = os.path.join(tmpdir, "aws_calls.log")

            def write_mock(name, body):
                path = os.path.join(bin_dir, name)
                with open(path, "w") as f:
                    f.write(body)
                os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)

            # mock aws CLI: 실제 API로 확인한 쿼리와 정확히 같을 때만 응답한다
            write_mock(
                "aws",
                "#!" + sys.executable + "\n"
                "import os, sys\n"
                "args = sys.argv[1:]\n"
                "with open(" + repr(log_file) + ", 'a') as f:\n"
                "    f.write(' '.join(args) + '\\n')\n"
                "def val(flag):\n"
                "    return args[args.index(flag) + 1] if flag in args else None\n"
                "if args[:2] == ['ec2', 'describe-network-interfaces']:\n"
                "    query = val('--query')\n"
                "    eni_query = \"NetworkInterfaces[?Attachment.InstanceId=='i-nat-test' && Attachment.Status=='attached'].NetworkInterfaceId\"\n"
                "    eip_filters = ['Name=attachment.instance-id,Values=i-nat-test', 'Name=attachment.device-index,Values=0']\n"
                "    if val('--network-interface-ids') == 'eni-floating-1' and query == eni_query:\n"
                "        if os.environ.get('MOCK_ENI_ATTACHED') == '1':\n"
                "            print('eni-floating-1')\n"
                "    elif '--filters' in args and args[args.index('--filters') + 1:args.index('--filters') + 3] == eip_filters \\\n"
                "            and query == 'NetworkInterfaces[0].Association.AllocationId':\n"
                "        print(os.environ.get('MOCK_EIP_ALLOC', 'None'))\n"
                "sys.exit(0)\n",
            )

            # mock curl (IMDSv2)
            write_mock(
                "curl",
                '#!/bin/sh\n'
                'case "$*" in\n'
                '  *instance-id*) echo "i-nat-test" ;;\n'
                '  *placement/region*) echo "ap-northeast-2" ;;\n'
                '  *) echo "mock-token" ;;\n'
                'esac\n'
                'exit 0\n',
            )
            write_mock("systemctl", "#!/bin/sh\nexit 0\n")
            # mock sysctl (IP 포워딩 활성)
            write_mock("sysctl", "#!/bin/sh\necho 1\nexit 0\n")

            rule_missing = '#!/bin/sh\necho "-P POSTROUTING ACCEPT"\nexit 0\n'
            rule_installed = (
                '#!/bin/sh\n'
                'echo "-A POSTROUTING -o ens5 -m comment --comment \\"NAT routing rule installed by fck-nat\\" -j MASQUERADE"\n'
                'exit 0\n'
            )

            # /etc/fck-nat.conf 쓰기를 임시 디렉터리로 리디렉션
            script_mod = script.replace("/etc/fck-nat.conf", os.path.join(tmpdir, "fck-nat.conf"))

            def run(iptables_body, eni_attached, eip_alloc):
                write_mock("iptables", iptables_body)
                open(log_file, "w").close()
                env = os.environ.copy()
                env["PATH"] = bin_dir + ":" + env["PATH"]
                env["MOCK_ENI_ATTACHED"] = eni_attached
                env["MOCK_EIP_ALLOC"] = eip_alloc
                proc = subprocess.run(["sh", "-c", script_mod], env=env, capture_output=True, text=True)
                with open(log_file, "r") as f:
                    return proc.returncode, f.read()

            failure_cases = [
                ("fck-nat NAT rule missing", rule_missing, "1", "eipalloc-static-1"),
                ("floating ENI not attached", rule_installed, "0", "eipalloc-static-1"),
                ("static EIP not associated", rule_installed, "1", "None"),
                ("other EIP associated", rule_installed, "1", "eipalloc-other"),
            ]
            for name, iptables_body, eni_attached, eip_alloc in failure_cases:
                returncode, logs = run(iptables_body, eni_attached, eip_alloc)
                self.assertEqual(returncode, 1, f"User data script must exit 1 when {name}")
                self.assertIn("--lifecycle-action-result ABANDON", logs, name)
                self.assertNotIn("--lifecycle-action-result CONTINUE", logs, name)
                print(f"  Step 1: {name} -> ABANDON called and exit code 1 verified.")

            returncode, logs = run(rule_installed, "1", "eipalloc-static-1")
            self.assertEqual(returncode, 0, "User data script must exit 0 on success")
            self.assertIn("--lifecycle-action-result CONTINUE", logs)
            self.assertIn("--instance-id i-nat-test", logs)
            print("  Step 2: ENI attached, NAT rule installed, static EIP associated -> CONTINUE and exit code 0 verified.")
            print("✅ Test 12 (User Data Real Subprocess Execution for Failure & Success): PASSED")

    def test_lambda_iam_policy_and_role_permissions_and_access_denied_handling(self):
        """
        13. [Lambda IAM 역할 및 권한 검증]
            1) failover.tf의 failover_lambda IAM 정책에 ec2:DescribeNetworkInterfaces,
               autoscaling:DescribeAutoScalingInstances가 정의되어 있고 실제 역할에 연결되었는지 검증
            2) 런타임에 DescribeNetworkInterfaces에서 AccessDenied 발생 시 안전하게 보류(DEFERRED)되고,
               권한 정상 시 원활하게 검증을 통과하는지 검증
        """
        from botocore.exceptions import ClientError

        failover_tf_path = os.path.join(
            os.path.dirname(__file__), "..", "failover.tf"
        )
        with open(failover_tf_path, "r", encoding="utf-8") as f:
            content = f.read()

        # IAM 정책 선언 검증
        self.assertIn('"ec2:DescribeNetworkInterfaces"', content)
        self.assertIn('"autoscaling:DescribeAutoScalingInstances"', content)
        self.assertIn('"autoscaling:DescribeAutoScalingGroups"', content)
        self.assertIn('resource "aws_iam_role_policy_attachment" "failover_lambda"', content)
        self.assertIn('role       = aws_iam_role.failover_lambda.name', content)
        self.assertIn('role             = aws_iam_role.failover_lambda.arn', content)
        print("  Step 1: Terraform IAM Policy & Role Attachment verified in failover.tf.")

        # 런타임 시뮬레이션: AccessDenied 발생 시 안전 보류(Fail-closed) 검증
        self.mock_floating_eni.side_effect = ClientError(
            {"Error": {"Code": "AccessDenied", "Message": "User is not authorized to perform: ec2:DescribeNetworkInterfaces"}},
            "DescribeNetworkInterfaces"
        )
        is_ready, inst_id, reason = failover.is_floating_eni_ready("eni-nat11111")
        self.assertFalse(is_ready)
        self.assertIn("AccessDenied", reason)
        print("  Step 2: AccessDenied exception handled safely (Fail-closed DEFERRED).")

        # 런타임 시뮬레이션: 권한 부여 시 정상 통과 검증
        self.mock_floating_eni.side_effect = None
        self.mock_floating_eni.return_value = {
            "NetworkInterfaces": [
                {
                    "NetworkInterfaceId": "eni-nat11111",
                    "Status": "in-use",
                    "Attachment": {
                        "Status": "attached",
                        "InstanceId": "i-01111111",
                        "DeviceIndex": 1,
                    },
                }
            ]
        }
        is_ready_ok, inst_id_ok, reason_ok = failover.is_floating_eni_ready("eni-nat11111")
        self.assertTrue(is_ready_ok)
        self.assertEqual(reason_ok, "Ready")
        print("  Step 3: Permission granted -> is_floating_eni_ready returns True.")
        print("✅ Test 13 (Lambda IAM Policy, Role Attachment & Runtime AccessDenied Handling): PASSED")

    def test_auto_assigned_public_ip_without_static_eip_deferred(self):
        """
        14. [PR 리뷰 검증 - 고정 EIP 준비 판정 강화]
            Launch Template의 associate_public_ip_address = true로 인해 임시 공인 IP만 있고,
            fck-nat에 의한 고정 EIP(AllocationId)가 아직 바인딩되지 않은 경우:
            1) is_instance_eip_ready()가 False 및 임시 공인 IP 안내 사유를 반환하는지 검증
            2) is_floating_eni_ready()가 False를 반환하여 조기 페일백이 방지되는지 검증
            3) 알람 OK 및 Reconcile 이벤트 수신 시 FAILBACK_DEFERRED / DEFERRED로 안전 보류되는지 검증
            4) fck-nat가 고정 EIP(AllocationId)를 연결하면 정상적으로 Ready 및 페일백/Reconcile되는지 검증
        """
        # Step 1: 임시 자동 할당 공인 IP만 존재 (AllocationId 없음)
        self.primary_eni_association["i-01111111"] = {"PublicIp": "54.180.1.1"}

        # 1) is_instance_eip_ready 검증
        eip_ready, eip_reason = failover.is_instance_eip_ready("i-01111111", expected_allocation_id="eipalloc-11111")
        self.assertFalse(eip_ready)
        self.assertIn("auto-assigned public IP", eip_reason)
        self.assertIn("static EIP (AllocationId) is not associated yet", eip_reason)
        print("  Step 1: Auto-assigned public IP without AllocationId -> is_instance_eip_ready returns False.")

        # 2) is_floating_eni_ready 검증
        is_ready, inst_id, reason = failover.is_floating_eni_ready("eni-nat11111")
        self.assertFalse(is_ready)
        self.assertIn("auto-assigned public IP", reason)
        print("  Step 2: Floating ENI readiness blocked by unassociated static EIP -> returns False.")

        # 3) CloudWatch Alarm OK 수신 시 FAILBACK_DEFERRED 검증
        event_ok = {
            "source": "aws.cloudwatch",
            "alarmData": {
                "alarmName": "fundit-dev-nat-1-status-check",
                "state": {"value": "OK"},
            },
        }
        res_ok = failover.lambda_handler(event_ok, None)
        self.assertEqual(res_ok["result"]["status"], "FAILBACK_DEFERRED")
        self.assertIn("auto-assigned public IP", res_ok["result"]["reason"])
        self.mock_ec2.replace_route.assert_not_called()
        print("  Step 3: Alarm OK during temporary public IP -> FAILBACK_DEFERRED and route preserved.")

        # Step 4: fck-nat에 의해 고정 EIP(AllocationId="eipalloc-11111")가 정상 연결됨
        self.primary_eni_association["i-01111111"] = {"PublicIp": "3.35.1.1", "AllocationId": "eipalloc-11111"}

        eip_ready_ok, eip_reason_ok = failover.is_instance_eip_ready("i-01111111", expected_allocation_id="eipalloc-11111")
        self.assertTrue(eip_ready_ok)
        self.assertIn("Static EIP associated", eip_reason_ok)

        # Alarm OK 재수신 시 정상 페일백 실행 검증
        res_failback = failover.lambda_handler(event_ok, None)
        self.assertEqual(res_failback["result"]["status"], "UPDATED")
        self.mock_ec2.replace_route.assert_called_once_with(
            RouteTableId="rtb-0aaa1111",
            DestinationCidrBlock="0.0.0.0/0",
            NetworkInterfaceId="eni-nat11111",
        )
        print("  Step 4: Static EIP associated -> Verified and Route Table A restored to NAT-1 Floating ENI.")
        print("✅ Test 14 (Auto-assigned Public IP without Static EIP Deferred -> Verified after EIP Bound): PASSED")

    def test_asg_unregistered_instance_fails_closed(self):
        """
        15. [PR 리뷰 검증 - ASG 미등록 인스턴스 Fail-closed 검증]
            NAT 인스턴스는 ASG 관리가 필수 전제이므로:
            1) ASG 조회 결과가 빈 배열(AutoScalingInstances: [])인 경우 True가 아닌 False를 반환하는지 검증
            2) instance_id가 None이거나 빈 문자열인 경우 False를 반환하는지 검증
            3) 미등록 인스턴스에 대해 is_floating_eni_ready()가 Fail-closed로 준비 미완료를 반환하는지 검증
        """
        # Step 1: ASG 조회 결과가 빈 경우
        self.mock_asg.describe_auto_scaling_instances.side_effect = None
        self.mock_asg.describe_auto_scaling_instances.return_value = {
            "AutoScalingInstances": []
        }

        asg_ready, asg_reason = failover.is_instance_asg_inservice("i-unregistered-999")
        self.assertFalse(asg_ready)
        self.assertIn("not registered in any ASG", asg_reason)
        print("  Step 1: Empty ASG query result -> is_instance_asg_inservice returns False (Fail-closed).")

        # Step 2: instance_id가 비어있는 경우
        asg_ready_empty, asg_reason_empty = failover.is_instance_asg_inservice("")
        self.assertFalse(asg_ready_empty)
        self.assertEqual(asg_reason_empty, "No instance ID")
        print("  Step 2: Empty instance ID -> returns False.")

        # Step 3: Floating ENI 확인 시 ASG 미등록으로 인해 차단되는지 검증
        is_ready, inst_id, reason = failover.is_floating_eni_ready("eni-nat11111")
        self.assertFalse(is_ready)
        self.assertIn("not registered in any ASG", reason)
        print("  Step 3: is_floating_eni_ready blocked by unregistered ASG -> returns False.")
        print("✅ Test 15 (ASG Unregistered Instance Fail-Closed Verification): PASSED")


if __name__ == "__main__":
    unittest.main()


