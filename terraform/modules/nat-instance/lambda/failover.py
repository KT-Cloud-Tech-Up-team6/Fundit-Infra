import json
import logging
import os
import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2_client = boto3.client("ec2")
sns_client = boto3.client("sns")

# 환경 변수 로드
ROUTE_TABLE_A_ID = os.environ.get("ROUTE_TABLE_A_ID")
ROUTE_TABLE_C_ID = os.environ.get("ROUTE_TABLE_C_ID")
NAT_1_ENI_ID = os.environ.get("NAT_1_ENI_ID")
NAT_2_ENI_ID = os.environ.get("NAT_2_ENI_ID")
NAT_1_INSTANCE_ID = os.environ.get("NAT_1_INSTANCE_ID")
NAT_2_INSTANCE_ID = os.environ.get("NAT_2_INSTANCE_ID")
NAT_1_TAG_NAME = os.environ.get("NAT_1_TAG_NAME", "fundit-dev-nat-1")
NAT_2_TAG_NAME = os.environ.get("NAT_2_TAG_NAME", "fundit-dev-nat-2")
ALERT_SNS_TOPIC_ARN = os.environ.get("ALERT_SNS_TOPIC_ARN")


def get_instance_name_tag(instance_id):
    """인스턴스의 Name 태그 값을 조회합니다."""
    if not instance_id:
        return None
    try:
        resp = ec2_client.describe_instances(InstanceIds=[instance_id])
        reservations = resp.get("Reservations", [])
        if reservations and reservations[0].get("Instances"):
            tags = reservations[0]["Instances"][0].get("Tags", [])
            for t in tags:
                if t.get("Key") == "Name":
                    return t.get("Value")
        return None
    except Exception as e:
        logger.warning(f"Failed to fetch tags for {instance_id}: {e}")
        return None


def is_instance_healthy(instance_id):
    """
    상대방 EC2 인스턴스의 실제 런타임 상태를 조회합니다.
    InstanceState == 'running' 및 InstanceStatus == 'ok', SystemStatus == 'ok' 여부를 검증합니다.
    동시 장애 시 레이스 컨디션으로 인한 상호 교차 라우팅(Cross-routing dead instances)을 방지합니다.
    """
    if not instance_id:
        return False
    try:
        response = ec2_client.describe_instance_status(
            InstanceIds=[instance_id], IncludeAllInstances=True
        )
        statuses = response.get("InstanceStatuses", [])
        if not statuses:
            logger.warning(f"No instance status record found for {instance_id}")
            return False

        status_data = statuses[0]
        state = status_data.get("InstanceState", {}).get("Name")
        if state != "running":
            logger.warning(f"Partner instance {instance_id} state is '{state}' (not running).")
            return False

        inst_status = status_data.get("InstanceStatus", {}).get("Status")
        sys_status = status_data.get("SystemStatus", {}).get("Status")

        is_healthy = inst_status == "ok" and sys_status == "ok"
        if not is_healthy:
            logger.warning(
                f"Partner instance {instance_id} check failed: InstanceStatus='{inst_status}', SystemStatus='{sys_status}'"
            )
        return is_healthy
    except ClientError as e:
        logger.error(f"Failed to describe instance status for {instance_id}: {e}")
        return False


def send_dual_failure_alert(route_table_id, target_instance_id, partner_instance_id, reason):
    """
    DUAL_FAILURE_ABORTED 발생 시 운영자 알림을 위해 SNS 토픽으로 경보 메시지를 발행합니다.
    향후 Slack/Discord Webhook Lambda 또는 Email 구독자가 연결될 수 있는 알림 Hub 역할을 수행합니다.
    """
    if not ALERT_SNS_TOPIC_ARN:
        logger.info("ALERT_SNS_TOPIC_ARN not configured. Skipping SNS alert.")
        return

    subject = "[CRITICAL] Dual NAT Failure Detected - Manual Intervention Required"
    message = (
        f"🚨 [CRITICAL ALERT] NAT Dual Failure Aborted\n\n"
        f"- Target Route Table: {route_table_id}\n"
        f"- Failing NAT Instance: {target_instance_id}\n"
        f"- Partner NAT Instance: {partner_instance_id}\n"
        f"- Reason: {reason}\n\n"
        f"Automatic failover has been ABORTED to prevent routing blackhole or circular loops.\n"
        f"Immediate operational intervention is required to inspect NAT instances and restore routing."
    )

    try:
        logger.info(f"Publishing critical dual failure alert to SNS topic {ALERT_SNS_TOPIC_ARN}")
        sns_client.publish(
            TopicArn=ALERT_SNS_TOPIC_ARN,
            Subject=subject,
            Message=message,
        )
    except Exception as e:
        logger.error(f"Failed to publish SNS dual failure alert: {e}")


def handle_ec2_state_change(event):
    """
    EventBridge EC2 Instance State-change Notification을 처리합니다.
    - 테라폼 프로비저닝 순서 레이스 컨디션을 방지하기 위해 Name 태그(fundit-dev-nat-*)로 대상을 동적 판별합니다.
    - state == 'running': 인스턴스 신규 생성/재시작 시 최신 Live ENI로 담당 Route Table 자동 Reconcile
    - state in ['stopped', 'shutting-down', 'terminated']: 인스턴스 중지 시 즉각 Failover 트리거
    """
    detail = event.get("detail", {})
    instance_id = detail.get("instance-id")
    state = detail.get("state")

    # Name 태그 및 Instance ID 매칭으로 NAT 인스턴스 판별
    name_tag = get_instance_name_tag(instance_id)
    is_nat_1 = (name_tag == NAT_1_TAG_NAME) or (instance_id == NAT_1_INSTANCE_ID)
    is_nat_2 = (name_tag == NAT_2_TAG_NAME) or (instance_id == NAT_2_INSTANCE_ID)

    if not is_nat_1 and not is_nat_2:
        logger.info(
            f"EC2 state-change: Instance {instance_id} (Name='{name_tag}') is not a managed NAT instance. Ignored."
        )
        return {"status": "IGNORED", "reason": "Not a managed NAT instance"}

    nat_name = "NAT-1" if is_nat_1 else "NAT-2"
    logger.info(f"Detected EC2 state-change for {nat_name} ({instance_id}): State='{state}'")

    # 1. 인스턴스 기동 시 Route Reconciliation
    # EC2 running 직후에는 OS/fck-nat 초기화가 덜 끝났을 수 있으므로,
    # is_instance_healthy()가 True일 때만 Reconcile하고 아직 준비 전이면 기존 failover 라우트를 유지합니다.
    if state == "running":
        if not is_instance_healthy(instance_id):
            logger.info(
                f"⏳ [RECONCILIATION DEFERRED] {nat_name} ({instance_id}) is running but not yet fully healthy (booting/initializing). "
                f"Keeping current route intact. CloudWatch OK event will restore the route once 2/2 status checks pass."
            )
            return {
                "status": "DEFERRED",
                "reason": f"{nat_name} is running but not yet healthy. Awaiting CloudWatch OK event.",
                "instance_id": instance_id,
            }

        if is_nat_1:
            target_rtb = ROUTE_TABLE_A_ID
            live_eni = get_live_instance_eni(instance_id, NAT_1_ENI_ID)
        else:
            target_rtb = ROUTE_TABLE_C_ID
            live_eni = get_live_instance_eni(instance_id, NAT_2_ENI_ID)

        logger.info(
            f"🔄 [RECONCILIATION] {nat_name} ({instance_id}) is running and healthy. "
            f"Reconciling Route Table {target_rtb} to Live ENI {live_eni}..."
        )
        result = update_route(target_rtb, live_eni)
        return {
            "status": "RECONCILED",
            "instance_id": instance_id,
            "route_table_id": target_rtb,
            "eni_id": live_eni,
            "detail": result,
        }

    # 2. 인스턴스 중지/종료 시 즉각 Failover
    elif state in ["stopped", "shutting-down", "terminated"]:
        logger.warning(
            f"🚨 [FAST FAILOVER] {nat_name} ({instance_id}) entered '{state}' state. Triggering failover..."
        )
        live_nat_1_eni = get_live_instance_eni(NAT_1_INSTANCE_ID, NAT_1_ENI_ID)
        live_nat_2_eni = get_live_instance_eni(NAT_2_INSTANCE_ID, NAT_2_ENI_ID)

        if is_nat_1:
            partner_healthy = is_instance_healthy(NAT_2_INSTANCE_ID)
            # DUAL_FAILURE_ABORTED는 상대 NAT의 실제 health가 False일 때만 반환
            if not partner_healthy:
                reason = f"Partner NAT-2 is unhealthy while NAT-1 entered '{state}'"
                logger.critical(f"🚨🚨 DUAL NAT FAILURE DETECTED: {reason}")
                send_dual_failure_alert(ROUTE_TABLE_A_ID, instance_id, NAT_2_INSTANCE_ID, reason)
                return {
                    "statusCode": 500,
                    "status": "DUAL_FAILURE_ABORTED",
                    "reason": reason,
                    "route_table_id": ROUTE_TABLE_A_ID,
                }

            # 상대 NAT-2가 살아있다면, 상대 Route가 NAT-1을 가리키고 있었더라도 먼저 상대 Route 복구 후 failover
            partner_current_eni = get_current_nat_eni(ROUTE_TABLE_C_ID)
            if partner_current_eni == live_nat_1_eni:
                logger.warning(
                    f"Route Table C was pointing to dead NAT-1 ({live_nat_1_eni}), "
                    f"but NAT-2 is healthy! Restoring Route Table C -> NAT-2 Live ENI ({live_nat_2_eni}) first."
                )
                update_route(ROUTE_TABLE_C_ID, live_nat_2_eni)

            res = update_route(ROUTE_TABLE_A_ID, live_nat_2_eni)
            return {"status": "FAILOVER_TRIGGERED", "result": res}
        else:
            partner_healthy = is_instance_healthy(NAT_1_INSTANCE_ID)
            if not partner_healthy:
                reason = f"Partner NAT-1 is unhealthy while NAT-2 entered '{state}'"
                logger.critical(f"🚨🚨 DUAL NAT FAILURE DETECTED: {reason}")
                send_dual_failure_alert(ROUTE_TABLE_C_ID, instance_id, NAT_1_INSTANCE_ID, reason)
                return {
                    "statusCode": 500,
                    "status": "DUAL_FAILURE_ABORTED",
                    "reason": reason,
                    "route_table_id": ROUTE_TABLE_C_ID,
                }

            partner_current_eni = get_current_nat_eni(ROUTE_TABLE_A_ID)
            if partner_current_eni == live_nat_2_eni:
                logger.warning(
                    f"Route Table A was pointing to dead NAT-2 ({live_nat_2_eni}), "
                    f"but NAT-1 is healthy! Restoring Route Table A -> NAT-1 Live ENI ({live_nat_1_eni}) first."
                )
                update_route(ROUTE_TABLE_A_ID, live_nat_1_eni)

            res = update_route(ROUTE_TABLE_C_ID, live_nat_1_eni)
            return {"status": "FAILOVER_TRIGGERED", "result": res}

    return {"status": "IGNORED", "reason": f"Unhandled state '{state}'"}




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
    if isinstance(event, dict) and "alarmData" in event:
        alarm_data = event.get("alarmData", {})
        new_state = alarm_data.get("state", {}).get("value")
        alarm_name = alarm_data.get("alarmName")

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
    CloudWatch Alarm 및 EventBridge 이벤트를 처리합니다.
    - CloudWatch Alarm ALARM: NAT 인스턴스 장애 시 파트너 헬스체크 후 페일오버 (동시 장애 레이스 컨디션 방지)
    - CloudWatch Alarm OK: NAT 정상 복구 시 페일백
    - EventBridge EC2 state-change: NAT 신규 생성/재시작 시 최신 Live ENI로 Route Reconciliation
    """
    logger.info(f"Received event: {json.dumps(event)}")

    # 0. EventBridge EC2 State-change Notification (Reconciliation) 확인
    if (
        isinstance(event, dict)
        and event.get("source") == "aws.ec2"
        and event.get("detail-type") == "EC2 Instance State-change Notification"
    ):
        res = handle_ec2_state_change(event)
        return {"statusCode": 200, "result": res}

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
    if is_nat_1:
        if new_state == "ALARM":
            logger.info("🚨 NAT-1 FAILED: Checking partner (NAT-2) status before failover...")
            partner_healthy = is_instance_healthy(NAT_2_INSTANCE_ID)

            # DUAL_FAILURE_ABORTED는 상대 NAT의 실제 health가 false일 때만 반환
            if not partner_healthy:
                reason = f"Partner NAT-2 ({NAT_2_INSTANCE_ID}) health check failed (healthy={partner_healthy})"
                logger.critical(
                    f"🚨🚨 CRITICAL: DUAL NAT FAILURE DETECTED! {reason}. "
                    f"Both NAT instances are DOWN! "
                    f"Aborting failover to dead instance to avoid circular routing. Manual intervention required!"
                )
                send_dual_failure_alert(
                    route_table_id=ROUTE_TABLE_A_ID,
                    target_instance_id=NAT_1_INSTANCE_ID,
                    partner_instance_id=NAT_2_INSTANCE_ID,
                    reason=reason,
                )
                return {
                    "statusCode": 500,
                    "status": "DUAL_FAILURE_ABORTED",
                    "reason": f"Both NAT instances are down ({reason}). Failover skipped to prevent circular routing.",
                    "route_table_id": ROUTE_TABLE_A_ID,
                }

            # 상대 NAT-2가 실제로 healthy하다면:
            # 상대 Route Table C가 죽은 NAT-1을 가리키고 있었더라도, 먼저 상대 RTB-C를 NAT-2 Live ENI로 복구!
            partner_current_eni = get_current_nat_eni(ROUTE_TABLE_C_ID)
            if partner_current_eni == live_nat_1_eni:
                logger.warning(
                    f"Route Table C was pointing to dead NAT-1 ({live_nat_1_eni}), "
                    f"but NAT-2 is healthy! Restoring Route Table C -> NAT-2 Live ENI ({live_nat_2_eni}) first."
                )
                update_route(ROUTE_TABLE_C_ID, live_nat_2_eni)

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
            partner_healthy = is_instance_healthy(NAT_1_INSTANCE_ID)

            if not partner_healthy:
                reason = f"Partner NAT-1 ({NAT_1_INSTANCE_ID}) health check failed (healthy={partner_healthy})"
                logger.critical(
                    f"🚨🚨 CRITICAL: DUAL NAT FAILURE DETECTED! {reason}. "
                    f"Both NAT instances are DOWN! "
                    f"Aborting failover to dead instance to avoid circular routing. Manual intervention required!"
                )
                send_dual_failure_alert(
                    route_table_id=ROUTE_TABLE_C_ID,
                    target_instance_id=NAT_2_INSTANCE_ID,
                    partner_instance_id=NAT_1_INSTANCE_ID,
                    reason=reason,
                )
                return {
                    "statusCode": 500,
                    "status": "DUAL_FAILURE_ABORTED",
                    "reason": f"Both NAT instances are down ({reason}). Failover skipped to prevent circular routing.",
                    "route_table_id": ROUTE_TABLE_C_ID,
                }

            partner_current_eni = get_current_nat_eni(ROUTE_TABLE_A_ID)
            if partner_current_eni == live_nat_2_eni:
                logger.warning(
                    f"Route Table A was pointing to dead NAT-2 ({live_nat_2_eni}), "
                    f"but NAT-1 is healthy! Restoring Route Table A -> NAT-1 Live ENI ({live_nat_1_eni}) first."
                )
                update_route(ROUTE_TABLE_A_ID, live_nat_1_eni)

            logger.info("Triggering Failover for Route Table C -> NAT-1 ENI")
            res = update_route(ROUTE_TABLE_C_ID, live_nat_1_eni)
        elif new_state == "OK":
            logger.info("✅ NAT-2 RECOVERED: Triggering Failback for Route Table C -> NAT-2 ENI")
            res = update_route(ROUTE_TABLE_C_ID, live_nat_2_eni)
        else:
            logger.info(f"NAT-2 entered state '{new_state}'. No action taken.")
            res = {"status": "IGNORED", "state": new_state}

    return {"statusCode": 200, "result": res}


