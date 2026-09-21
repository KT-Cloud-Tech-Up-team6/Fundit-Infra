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


def parse_cloudwatch_event(event):
    """
    CloudWatch Alarm 직접 호출 페이로드, SNS 래핑 페이로드, 레거시 페이로드를
    모두 지원하여 (new_state, alarm_name, instance_id) 튜플을 반환합니다.
    """
    # 1. SNS 이벤트 래핑 해제
    if isinstance(event, dict) and "Records" in event and len(event["Records"]) > 0:
        record = event["Records"][0]
        if "Sns" in record and "Message" in record["Sns"]:
            try:
                event = json.loads(record["Sns"]["Message"])
            except Exception as e:
                logger.warning(f"Failed to parse SNS message as JSON: {e}")

    new_state = None
    alarm_name = None
    instance_id = None

    # 2. CloudWatch Alarm 직접 호출 페이로드 (Direct Invoke 규격)
    # 이벤트 경로: event["alarmData"]["state"]["value"], event["alarmData"]["alarmName"]
    if isinstance(event, dict) and "alarmData" in event:
        alarm_data = event.get("alarmData", {})
        new_state = alarm_data.get("state", {}).get("value")
        alarm_name = alarm_data.get("alarmName")

        # configuration.metrics[].metricStat.metric.dimensions 에서 InstanceId 추출
        metrics = alarm_data.get("configuration", {}).get("metrics", [])
        for m in metrics:
            metric_stat = m.get("metricStat", {})
            metric_info = metric_stat.get("metric", {})
            dims = metric_info.get("dimensions", {})
            if isinstance(dims, dict) and "InstanceId" in dims:
                instance_id = dims["InstanceId"]
                break
            elif isinstance(dims, list):
                for d in dims:
                    if d.get("name") == "InstanceId":
                        instance_id = d.get("value")
                        break
                if instance_id:
                    break

    # 3. 최상위 레거시/표준 구조 백업 파싱
    if not new_state and isinstance(event, dict):
        new_state = event.get("NewStateValue")
    if not alarm_name and isinstance(event, dict):
        alarm_name = event.get("AlarmName")
    if not instance_id and isinstance(event, dict):
        trigger = event.get("Trigger", {})
        for dim in trigger.get("Dimensions", []):
            if dim.get("name") == "InstanceId":
                instance_id = dim.get("value")
                break

    return new_state, alarm_name, instance_id


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


def get_live_instance_eni(instance_id, fallback_eni):
    """인스턴스의 현재 활성 Primary ENI를 동적으로 조회합니다 (인스턴스 교체 대응)."""
    if not instance_id:
        return fallback_eni
    try:
        resp = ec2_client.describe_instances(InstanceIds=[instance_id])
        reservations = resp.get("Reservations", [])
        if reservations and reservations[0].get("Instances"):
            inst = reservations[0]["Instances"][0]
            for iface in inst.get("NetworkInterfaces", []):
                if iface.get("Attachment", {}).get("DeviceIndex") == 0:
                    live_eni = iface.get("NetworkInterfaceId")
                    if live_eni:
                        return live_eni
        return fallback_eni
    except Exception as e:
        logger.warning(
            f"Failed to fetch live ENI for {instance_id}, using fallback {fallback_eni}: {e}"
        )
        return fallback_eni


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

    # 1. 이벤트 파싱 (Direct Invoke, SNS, Legacy 모두 지원)
    new_state, alarm_name, target_instance = parse_cloudwatch_event(event)

    if not new_state:
        logger.warning("No state value found in event. Nothing to do.")
        return {"status": "IGNORED", "reason": "No state value in event"}

    logger.info(
        f"Parsed Alarm: State='{new_state}', AlarmName='{alarm_name}', InstanceId='{target_instance}'"
    )

    # 2. 대상 인스턴스 식별
    is_nat_1 = False
    is_nat_2 = False

    if target_instance:
        if target_instance == NAT_1_INSTANCE_ID:
            is_nat_1 = True
        elif target_instance == NAT_2_INSTANCE_ID:
            is_nat_2 = True

    # 인스턴스 ID 매칭이 안 된 경우 AlarmName으로 백업 판별
    if not is_nat_1 and not is_nat_2 and alarm_name:
        if "nat-1" in alarm_name.lower():
            is_nat_1 = True
        elif "nat-2" in alarm_name.lower():
            is_nat_2 = True

    if not is_nat_1 and not is_nat_2:
        logger.warning(
            f"Could not determine target NAT instance from AlarmName='{alarm_name}' or InstanceId='{target_instance}'"
        )
        return {"status": "IGNORED", "reason": "Target NAT instance unknown"}

    # 3. 최신 Live ENI 확인 (인스턴스 재생성 시 ENI 변경 대응)
    live_nat_1_eni = get_live_instance_eni(NAT_1_INSTANCE_ID, NAT_1_ENI_ID)
    live_nat_2_eni = get_live_instance_eni(NAT_2_INSTANCE_ID, NAT_2_ENI_ID)

    # 4. 상태별 페일오버 및 페일백 분기
    # - NAT-1 장애 (ALARM): AZ-a 라우팅 -> NAT-2 ENI로 변경 (Failover)
    # - NAT-1 복구 (OK):    AZ-a 라우팅 -> NAT-1 ENI로 복원 (Failback)
    # - NAT-2 장애 (ALARM): AZ-c 라우팅 -> NAT-1 ENI로 변경 (Failover)
    # - NAT-2 복구 (OK):    AZ-c 라우팅 -> NAT-2 ENI로 복원 (Failback)

    if is_nat_1:
        if new_state == "ALARM":
            logger.info("🚨 NAT-1 FAILED: Checking partner (NAT-2) status before failover...")
            partner_current_eni = get_current_nat_eni(ROUTE_TABLE_C_ID)
            # 상대방 라우팅이 이미 내 ENI를 가리키고 있다면, 상대방도 이미 다운된 상태임
            if partner_current_eni == live_nat_1_eni:
                logger.critical(
                    f"🚨🚨 CRITICAL: DUAL NAT FAILURE DETECTED! "
                    f"Route Table C is already pointing to NAT-1 ({live_nat_1_eni}), indicating NAT-2 is DOWN. "
                    f"Now NAT-1 is also FAILING. Both NAT instances are DOWN! "
                    f"Aborting failover to dead instance to avoid circular routing. Manual intervention required!"
                )
                return {
                    "statusCode": 500,
                    "status": "DUAL_FAILURE_ABORTED",
                    "reason": "Both NAT instances are down. Failover skipped to prevent circular routing.",
                    "route_table_id": ROUTE_TABLE_A_ID,
                }

            logger.info("Triggering Failover for Route Table A -> NAT-2 ENI")
            res = update_route(ROUTE_TABLE_A_ID, live_nat_2_eni)
        elif new_state == "OK":
            logger.info("✅ NAT-1 RECOVERED: Triggering Failback for Route Table A -> NAT-1 ENI")
            res = update_route(ROUTE_TABLE_A_ID, live_nat_1_eni)
        else:
            logger.info(f"NAT-1 entered state '{new_state}'. No action taken.")
            res = {"status": "IGNORED", "state": new_state}
    else:  # is_nat_2
        if new_state == "ALARM":
            logger.info("🚨 NAT-2 FAILED: Checking partner (NAT-1) status before failover...")
            partner_current_eni = get_current_nat_eni(ROUTE_TABLE_A_ID)
            if partner_current_eni == live_nat_2_eni:
                logger.critical(
                    f"🚨🚨 CRITICAL: DUAL NAT FAILURE DETECTED! "
                    f"Route Table A is already pointing to NAT-2 ({live_nat_2_eni}), indicating NAT-1 is DOWN. "
                    f"Now NAT-2 is also FAILING. Both NAT instances are DOWN! "
                    f"Aborting failover to dead instance to avoid circular routing. Manual intervention required!"
                )
                return {
                    "statusCode": 500,
                    "status": "DUAL_FAILURE_ABORTED",
                    "reason": "Both NAT instances are down. Failover skipped to prevent circular routing.",
                    "route_table_id": ROUTE_TABLE_C_ID,
                }

            logger.info("Triggering Failover for Route Table C -> NAT-1 ENI")
            res = update_route(ROUTE_TABLE_C_ID, live_nat_1_eni)
        elif new_state == "OK":
            logger.info("✅ NAT-2 RECOVERED: Triggering Failback for Route Table C -> NAT-2 ENI")
            res = update_route(ROUTE_TABLE_C_ID, live_nat_2_eni)
        else:
            logger.info(f"NAT-2 entered state '{new_state}'. No action taken.")
            res = {"status": "IGNORED", "state": new_state}

    return {"statusCode": 200, "result": res}
