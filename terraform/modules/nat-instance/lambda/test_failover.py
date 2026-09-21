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

        # 기본 인스턴스 정보 모의
        def default_describe_instances(InstanceIds):
            inst_id = InstanceIds[0]
            eni_id = "eni-nat11111" if inst_id == "i-01111111" else "eni-nat22222"
            return {
                "Reservations": [
                    {
                        "Instances": [
                            {
                                "NetworkInterfaces": [
                                    {
                                        "Attachment": {"DeviceIndex": 0},
                                        "NetworkInterfaceId": eni_id,
                                    }
                                ]
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

        # Mock: RTB-C(상대방)는 정상적으로 NAT-2를 바라보고 있음
        # Mock: RTB-A는 현재 NAT-1을 바라보고 있음
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
                            "NetworkInterfaceId": "eni-nat22222",  # 현재 failover된 상태
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

    def test_dual_failure_detection_route_table_circular(self):
        """3. 상대 라우트 테이블이 이미 내 ENI를 가리킬 때 DUAL_FAILURE_ABORTED 및 SNS 알림 검증"""
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

        # Mock: RTB-C(상대방)가 이미 NAT-1을 가리키고 있음 (즉, NAT-2가 먼저 다운되어 우회된 상태)
        self.mock_ec2.describe_route_tables.return_value = {
            "RouteTables": [
                {
                    "Routes": [
                        {
                            "DestinationCidrBlock": "0.0.0.0/0",
                            "NetworkInterfaceId": "eni-nat11111",  # 이미 NAT-1로 우회되어 있음
                        }
                    ]
                }
            ]
        }

        result = failover.lambda_handler(event, None)

        self.assertEqual(result["statusCode"], 500)
        self.assertEqual(result["status"], "DUAL_FAILURE_ABORTED")
        self.mock_ec2.replace_route.assert_not_called()
        self.mock_sns.publish.assert_called_once()
        print("✅ Test 3 (Dual NAT Failure via Route Table Circular): PASSED")

    def test_concurrent_dual_failure_race_condition(self):
        """4. [동시 장애 레이스 컨디션] 라우트 테이블은 정상이지만 상대 인스턴스 헬스체크 실패 시 failover 중단 검증"""
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

        # Mock 레이스 컨디션: RTB-C는 아직 NAT-2를 가리키고 있음 (아직 변경 전)
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

        # 하지만 파트너 NAT-2의 실제 EC2 상태가 impaired(장애) 상태임!
        self.mock_ec2.describe_instance_status.side_effect = None
        self.mock_ec2.describe_instance_status.return_value = {
            "InstanceStatuses": [
                {
                    "InstanceId": "i-02222222",
                    "InstanceState": {"Name": "running"},
                    "InstanceStatus": {"Status": "impaired"},  # 장애!
                    "SystemStatus": {"Status": "ok"},
                }
            ]
        }


        result = failover.lambda_handler(event, None)

        # 라우트 테이블만 보면 정상 같지만, 실제 EC2 상태를 확인하여 DUAL_FAILURE_ABORTED로 안전하게 중단해야 함!
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

        # 파트너 NAT-1의 인스턴스가 중지(stopped) 상태
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

        # SNS 발행 검증
        self.mock_sns.publish.assert_called_once()
        call_kwargs = self.mock_sns.publish.call_args[1]
        self.assertEqual(
            call_kwargs["TopicArn"],
            "arn:aws:sns:ap-northeast-2:123456789012:fundit-dev-nat-failover-alerts",
        )
        self.assertIn("Dual NAT Failure", call_kwargs["Subject"])
        self.assertIn("Target Route Table: rtb-0ccc2222", call_kwargs["Message"])
        print("✅ Test 5 (SNS Alert Publishing on Dual Failure): PASSED")

    def test_ec2_running_state_reconciliation(self):
        """6. [인스턴스 교체 대응] EventBridge EC2 running 이벤트 수신 시 새 Live ENI로 라우트 Reconcile 검증"""
        event = {
            "version": "0",
            "id": "12345678-1234-1234-1234-123456789012",
            "detail-type": "EC2 Instance State-change Notification",
            "source": "aws.ec2",
            "account": "123456789012",
            "time": "2026-09-21T07:45:00Z",
            "region": "ap-northeast-2",
            "resources": ["arn:aws:ec2:ap-northeast-2:123456789012:instance/i-01111111"],
            "detail": {
                "instance-id": "i-01111111",  # NAT-1이 새로 running 됨
                "state": "running",
            },
        }

        # 새 인스턴스의 Live ENI가 새로 할당된 eni-new-live-11111 이라고 가정
        self.mock_ec2.describe_instances.side_effect = None
        self.mock_ec2.describe_instances.return_value = {
            "Reservations": [
                {
                    "Instances": [
                        {
                            "NetworkInterfaces": [
                                {
                                    "Attachment": {"DeviceIndex": 0},
                                    "NetworkInterfaceId": "eni-new-live-11111",
                                }
                            ]
                        }
                    ]
                }
            ]
        }


        # 기존 라우트 테이블은 삭제된 구 ENI(eni-old-deleted)를 가리키고 있음
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

        result = failover.lambda_handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(result["result"]["status"], "RECONCILED")
        self.assertEqual(result["result"]["instance_id"], "i-01111111")
        self.assertEqual(result["result"]["route_table_id"], "rtb-0aaa1111")
        self.assertEqual(result["result"]["eni_id"], "eni-new-live-11111")

        # 새 Live ENI로 라우트 교체 확인
        self.mock_ec2.replace_route.assert_called_once_with(
            RouteTableId="rtb-0aaa1111",
            DestinationCidrBlock="0.0.0.0/0",
            NetworkInterfaceId="eni-new-live-11111",
        )
        print("✅ Test 6 (EC2 Running State Route Reconciliation): PASSED")


if __name__ == "__main__":
    unittest.main()
