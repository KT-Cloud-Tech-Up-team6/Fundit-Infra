import json
import logging
import os
import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2_client = boto3.client("ec2")

# 환경 변수 로드
ROUTE_TABLE_A_ID = os.environ.get("ROUTE_TABLE_A_ID")
ROUTE_TABLE_C_ID = os.environ.get("ROUTE_TABLE_C_ID")
NAT_1_ENI_ID = os.environ.get("NAT_1_ENI_ID")
NAT_2_ENI_ID = os.environ.get("NAT_2_ENI_ID")
NAT_1_INSTANCE_ID = os.environ.get("NAT_1_INSTANCE_ID")
NAT_2_INSTANCE_ID = os.environ.get("NAT_2_INSTANCE_ID")


def get_current_nat_eni(route_table_id):
    """현재 라우팅 테이블의 0.0.0.0/0 대상 ENI를 조회합니다."""
    try:
        response = ec2_client.describe_route_tables(RouteTableIds=[route_table_id])
        route_tables = response.get("RouteTables", [])
        if not route_tables:
            logger.warning(f"Route table {route_table_id} not found.")
            return None

        for route in route_tables[0].get("Routes", []):
            if route.get("DestinationCidrBlock") == "0.0.0.0/0":
                return route.get("NetworkInterfaceId")
        return None
    except ClientError as e:
        logger.error(f"Failed to describe route table {route_table_id}: {e}")
        raise


def update_route(route_table_id, target_eni_id):
    """라우팅 테이블의 0.0.0.0/0 대상을 target_eni_id로 업데이트합니다 (멱등성 보장)."""
    current_eni = get_current_nat_eni(route_table_id)
    if current_eni == target_eni_id:
        logger.info(
            f"Route table {route_table_id} 0.0.0.0/0 is already pointing to {target_eni_id}. No action needed."
        )
        return {
            "status": "SKIPPED",
            "reason": "Already pointing to target ENI",
            "route_table_id": route_table_id,
            "target_eni_id": target_eni_id,
        }

    try:
        logger.info(
            f"Replacing route in {route_table_id}: 0.0.0.0/0 -> {target_eni_id} (previous: {current_eni})"
        )
        ec2_client.replace_route(
            RouteTableId=route_table_id,
            DestinationCidrBlock="0.0.0.0/0",
            NetworkInterfaceId=target_eni_id,
        )
        logger.info(f"Successfully replaced route in {route_table_id} with {target_eni_id}")
        return {
            "status": "UPDATED",
            "route_table_id": route_table_id,
            "target_eni_id": target_eni_id,
            "previous_eni_id": current_eni,
        }
    except ClientError as e:
        if e.response["Error"]["Code"] == "InvalidRoute.NotFound":
            logger.warning(
                f"Route 0.0.0.0/0 not found in {route_table_id}. Creating new route..."
            )
            ec2_client.create_route(
                RouteTableId=route_table_id,
                DestinationCidrBlock="0.0.0.0/0",
                NetworkInterfaceId=target_eni_id,
            )
            logger.info(f"Successfully created route in {route_table_id} with {target_eni_id}")
            return {
                "status": "CREATED",
                "route_table_id": route_table_id,
                "target_eni_id": target_eni_id,
            }
        else:
            logger.error(f"Failed to update route in {route_table_id}: {e}")
            raise


def lambda_handler(event, context):
    """
    CloudWatch Alarm 이벤트를 처리하여 NAT 인스턴스 장애 시 페일오버, 정상 복구 시 페일백을 수행합니다.
    """
    logger.info(f"Received event: {json.dumps(event)}")

    # 1. 알람 상태 확인 (ALARM, OK 등)
    new_state = event.get("NewStateValue")
    alarm_name = event.get("AlarmName", "")

    if not new_state:
        logger.warning("No NewStateValue found in event. Nothing to do.")
        return {"status": "IGNORED", "reason": "No NewStateValue in event"}

    # 2. 대상 인스턴스 식별 (AlarmName 또는 Trigger Dimensions)
    target_instance = None
    trigger = event.get("Trigger", {})
    for dim in trigger.get("Dimensions", []):
        if dim.get("name") == "InstanceId":
            target_instance = dim.get("value")
            break

    is_nat_1 = False
    is_nat_2 = False

    if target_instance:
        if target_instance == NAT_1_INSTANCE_ID:
            is_nat_1 = True
        elif target_instance == NAT_2_INSTANCE_ID:
            is_nat_2 = True

    # 인스턴스 ID 매칭이 안 된 경우 AlarmName으로 백업 판별
    if not is_nat_1 and not is_nat_2:
        if "nat-1" in alarm_name.lower():
            is_nat_1 = True
        elif "nat-2" in alarm_name.lower():
            is_nat_2 = True

    if not is_nat_1 and not is_nat_2:
        logger.warning(
            f"Could not determine target NAT instance from AlarmName='{alarm_name}' or InstanceId='{target_instance}'"
        )
        return {"status": "IGNORED", "reason": "Target NAT instance unknown"}

    # 3. 상태별 페일오버 및 페일백 분기
    # - NAT-1 장애 (ALARM): AZ-a 라우팅 -> NAT-2 ENI로 변경 (Failover)
    # - NAT-1 복구 (OK):    AZ-a 라우팅 -> NAT-1 ENI로 복원 (Failback)
    # - NAT-2 장애 (ALARM): AZ-c 라우팅 -> NAT-1 ENI로 변경 (Failover)
    # - NAT-2 복구 (OK):    AZ-c 라우팅 -> NAT-2 ENI로 복원 (Failback)

    if is_nat_1:
        if new_state == "ALARM":
            logger.info("🚨 NAT-1 FAILED: Checking partner (NAT-2) status before failover...")
            partner_current_eni = get_current_nat_eni(ROUTE_TABLE_C_ID)
            if partner_current_eni == NAT_1_ENI_ID:
                logger.critical(
                    f"🚨🚨 CRITICAL: DUAL NAT FAILURE DETECTED! "
                    f"Route Table C is already pointing to NAT-1 ({NAT_1_ENI_ID}). "
                    f"Both NAT instances ({NAT_1_INSTANCE_ID}, {NAT_2_INSTANCE_ID}) appear to be DOWN. "
                    f"Outbound internet connectivity is degraded. Manual recovery or ASG self-healing required."
                )
            logger.info("Triggering Failover for Route Table A -> NAT-2 ENI")
            res = update_route(ROUTE_TABLE_A_ID, NAT_2_ENI_ID)
            if partner_current_eni == NAT_1_ENI_ID:
                res["dual_failure_warning"] = True
        elif new_state == "OK":
            logger.info("✅ NAT-1 RECOVERED: Triggering Failback for Route Table A -> NAT-1 ENI")
            res = update_route(ROUTE_TABLE_A_ID, NAT_1_ENI_ID)
        else:
            logger.info(f"NAT-1 entered state '{new_state}'. No action taken.")
            res = {"status": "IGNORED", "state": new_state}
    else:  # is_nat_2
        if new_state == "ALARM":
            logger.info("🚨 NAT-2 FAILED: Checking partner (NAT-1) status before failover...")
            partner_current_eni = get_current_nat_eni(ROUTE_TABLE_A_ID)
            if partner_current_eni == NAT_2_ENI_ID:
                logger.critical(
                    f"🚨🚨 CRITICAL: DUAL NAT FAILURE DETECTED! "
                    f"Route Table A is already pointing to NAT-2 ({NAT_2_ENI_ID}). "
                    f"Both NAT instances ({NAT_1_INSTANCE_ID}, {NAT_2_INSTANCE_ID}) appear to be DOWN. "
                    f"Outbound internet connectivity is degraded. Manual recovery or ASG self-healing required."
                )
            logger.info("Triggering Failover for Route Table C -> NAT-1 ENI")
            res = update_route(ROUTE_TABLE_C_ID, NAT_1_ENI_ID)
            if partner_current_eni == NAT_2_ENI_ID:
                res["dual_failure_warning"] = True
        elif new_state == "OK":
            logger.info("✅ NAT-2 RECOVERED: Triggering Failback for Route Table C -> NAT-2 ENI")
            res = update_route(ROUTE_TABLE_C_ID, NAT_2_ENI_ID)
        else:
            logger.info(f"NAT-2 entered state '{new_state}'. No action taken.")
            res = {"status": "IGNORED", "state": new_state}

    return {"statusCode": 200, "result": res}
