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

import failover


class TestNatFailoverLambda(unittest.TestCase):
    def setUp(self):
        self.mock_ec2 = MagicMock()
        failover.ec2_client = self.mock_ec2

    def test_direct_invoke_alarm_failover(self):
        """1. CloudWatch Alarm 직접 호출 페이로드 파싱 및 페일오버(Route Table A -> NAT-2) 검증"""
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

        def mock_describe_instances(InstanceIds):
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

        self.mock_ec2.describe_instances.side_effect = mock_describe_instances

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
                            "NetworkInterfaceId": "eni-nat22222",  # 현재는 failover된 상태
                        }
                    ]
                }
            ]
        }
        self.mock_ec2.describe_instances.return_value = {
            "Reservations": [
                {
                    "Instances": [
                        {
                            "NetworkInterfaces": [
                                {
                                    "Attachment": {"DeviceIndex": 0},
                                    "NetworkInterfaceId": "eni-nat11111",
                                }
                            ]
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

    def test_dual_failure_detection_and_abort(self):
        """3. 두 NAT 동시 장애 상황 감지 시 무의미한 교체 중단(DUAL_FAILURE_ABORTED) 검증"""
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

        # Mock: RTB-C(상대방)가 이미 NAT-1을 가리키고 있음 (즉, NAT-2도 이미 죽어서 넘어와 있던 상태)
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
        # 라우트 교체가 호출되지 않았는지 확인
        self.mock_ec2.replace_route.assert_not_called()
        print("✅ Test 3 (Dual NAT Failure Abort): PASSED")


if __name__ == "__main__":
    unittest.main()
