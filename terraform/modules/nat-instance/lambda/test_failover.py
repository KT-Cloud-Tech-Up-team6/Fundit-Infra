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
        failover.ec2_client = self.mock_ec2
        failover.sns_client = self.mock_sns
        failover.ALERT_SNS_TOPIC_ARN = (
            "arn:aws:sns:ap-northeast-2:123456789012:fundit-dev-nat-failover-alerts"
        )
        failover.NAT_1_TAG_NAME = "fundit-dev-nat-1"
        failover.NAT_2_TAG_NAME = "fundit-dev-nat-2"

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
            elif inst_id == "i-02222222":
                eni_id = "eni-nat22222"
                tag_name = "fundit-dev-nat-2"
            else:
                eni_id = "eni-unknown"
                tag_name = tag_name or "some-other-instance"

            return {
                "Reservations": [
                    {
                        "Instances": [
                            {
                                "InstanceId": inst_id or "i-unknown",
                                "State": {"Name": "running"},
                                "Tags": [{"Key": "Name", "Value": tag_name}],
                                "NetworkInterfaces": [
                                    {
                                        "Attachment": {"DeviceIndex": 0},
                                        "NetworkInterfaceId": eni_id,
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

        self.mock_ec2.describe_network_interfaces.side_effect = default_describe_network_interfaces

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
        self.mock_ec2.describe_network_interfaces.side_effect = None
        self.mock_ec2.describe_network_interfaces.return_value = {
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
                            "NetworkInterfaces": [
                                {
                                    "Attachment": {"DeviceIndex": 0},
                                    "NetworkInterfaceId": "eni-new-live-99999",
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

        self.mock_ec2.describe_network_interfaces.side_effect = None
        self.mock_ec2.describe_network_interfaces.return_value = {
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
                            "NetworkInterfaces": [
                                {
                                    "Attachment": {"DeviceIndex": 0},
                                    "NetworkInterfaceId": "eni-dynamic-live-nat2",
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

        self.mock_ec2.describe_network_interfaces.side_effect = None
        self.mock_ec2.describe_network_interfaces.return_value = {
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

        self.mock_ec2.describe_network_interfaces.side_effect = mock_eni_available
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

        self.mock_ec2.describe_network_interfaces.side_effect = mock_eni_attached
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
            60초 타임아웃 시 CONTINUE 대신 ABANDON을 전송하고 exit 1로 비정상 종료하여
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
        self.assertIn("systemctl is-active fck-nat", content)

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


if __name__ == "__main__":
    unittest.main()

