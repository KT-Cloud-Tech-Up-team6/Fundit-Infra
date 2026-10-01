import json
import logging
import os
import time
import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2_client = boto3.client("ec2")
sns_client = boto3.client("sns")
autoscaling_client = boto3.client("autoscaling")


# 환경 변수 로드
ROUTE_TABLE_A_ID = os.environ.get("ROUTE_TABLE_A_ID")
ROUTE_TABLE_C_ID = os.environ.get("ROUTE_TABLE_C_ID")
NAT_1_ENI_ID = os.environ.get("NAT_1_ENI_ID")
NAT_2_ENI_ID = os.environ.get("NAT_2_ENI_ID")
NAT_1_INSTANCE_ID = os.environ.get("NAT_1_INSTANCE_ID")
NAT_2_INSTANCE_ID = os.environ.get("NAT_2_INSTANCE_ID")
NAT_1_TAG_NAME = os.environ.get("NAT_1_TAG_NAME", "fundit-dev-nat-1")
NAT_2_TAG_NAME = os.environ.get("NAT_2_TAG_NAME", "fundit-dev-nat-2")
NAT_1_EIP_ALLOC_ID = os.environ.get("NAT_1_EIP_ALLOC_ID")
NAT_2_EIP_ALLOC_ID = os.environ.get("NAT_2_EIP_ALLOC_ID")
ALERT_SNS_TOPIC_ARN = os.environ.get("ALERT_SNS_TOPIC_ARN")


def get_live_instance_id_by_name(name_tag, max_retries=3, retry_delay=1.0):
    """
    지정된 Name 태그(예: fundit-dev-nat-1)를 가진 EC2 인스턴스 중
    running 또는 pending 상태인 인스턴스 ID를 동적으로 조회합니다.
    ASG에 의해 교체 진행 중이거나 일시적인 API 오류를 고려하여 제한된 재조회를 수행하며,
    (instance_id, is_api_error) 튜플을 반환하여 조회 실패와 인스턴스 부재를 구분합니다.
    """
    if not name_tag:
        return None, False

    last_error = None
    for attempt in range(1, max_retries + 1):
        try:
            resp = ec2_client.describe_instances(
                Filters=[
                    {"Name": "tag:Name", "Values": [name_tag]},
                    {"Name": "instance-state-name", "Values": ["pending", "running"]},
                ]
            )
            for reservation in resp.get("Reservations", []):
                for inst in reservation.get("Instances", []):
                    inst_id = inst.get("InstanceId")
                    if inst_id:
                        return inst_id, False

            # 인스턴스가 아직 등록/가동 중이지 않은 경우 짧은 대기 후 재조회
            if attempt < max_retries:
                logger.info(
                    f"No pending/running instance found for tag '{name_tag}' (attempt {attempt}/{max_retries}). "
                    f"Retrying in {retry_delay}s..."
                )
                time.sleep(retry_delay)
        except Exception as e:
            last_error = e
            logger.warning(
                f"DescribeInstances query failed for tag '{name_tag}' (attempt {attempt}/{max_retries}): {e}"
            )
            if attempt < max_retries:
                time.sleep(retry_delay)

    if last_error:
        logger.error(
            f"Failed to query instance for tag '{name_tag}' after {max_retries} retries due to API error: {last_error}"
        )
        return None, True

    return None, False


def get_partner_instance_id(is_nat_1):
    """
    상대방(Partner) NAT 인스턴스 ID를 안전하게 조회합니다.
    1. Name 태그 기반 동적 조회를 제한된 재시도로 수행합니다.
    2. API 조회 실패(is_api_error=True)인 경우 오래된 fallback_id를 반환하지 않고 (None, True)를 반환합니다.
    3. 조회는 성공했으나 인스턴스를 찾지 못한 경우, fallback_id가 지정되어 있다면 현재 실제 런타임 상태를
       단건 검증(running/pending 여부)하여 오래된/종료된 ID를 필터링합니다.
    4. 반환값: (partner_instance_id, is_api_error)
    """
    target_tag = NAT_2_TAG_NAME if is_nat_1 else NAT_1_TAG_NAME
    fallback_id = NAT_2_INSTANCE_ID if is_nat_1 else NAT_1_INSTANCE_ID

    live_id, is_api_error = get_live_instance_id_by_name(target_tag)
    if live_id:
        return live_id, False

    if is_api_error:
        logger.error(
            f"API error while discovering partner NAT ({target_tag}). Refusing to return stale fallback ID."
        )
        return None, True

    # 태그 조회 결과 인스턴스가 없는 경우: fallback_id가 유효한지 상태 확인 후 반환 (오래된 terminated ID 배제)
    if fallback_id:
        try:
            resp = ec2_client.describe_instances(InstanceIds=[fallback_id])
            for reservation in resp.get("Reservations", []):
                for inst in reservation.get("Instances", []):
                    st = inst.get("State", {}).get("Name")
                    if st in ["pending", "running"]:
                        logger.info(f"Fallback partner ID {fallback_id} verified in active state '{st}'.")
                        return fallback_id, False
                    else:
                        logger.warning(
                            f"Fallback partner ID {fallback_id} is in stale state '{st}'. Discarding."
                        )
        except Exception as e:
            logger.warning(f"Failed to verify fallback instance {fallback_id}: {e}")

    return None, False


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
        logger.warning("is_instance_healthy called with empty or None instance_id.")
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


def is_instance_asg_inservice(instance_id):
    """
    인스턴스가 Auto Scaling Group에 속해 있는 경우,
    LifecycleState가 'InService'인지 검증합니다.
    (Pending:Wait 상태 등 부트스트랩/Lifecycle Hook 미완료 시 조기 페일백 방지)
    NAT 인스턴스는 ASG 관리가 전제이므로, ASG 미등록 또는 조회 결과가 빈 경우
    Fail-closed(False)로 처리하여 조기 페일백 가드를 유지합니다.
    """
    if not instance_id:
        return False, "No instance ID"
    try:
        resp = autoscaling_client.describe_auto_scaling_instances(
            InstanceIds=[instance_id]
        )
        asg_instances = resp.get("AutoScalingInstances", [])
        if not asg_instances:
            # ASG 관리가 전제이므로 미등록 인스턴스는 Fail-closed 처리하여 조기 페일백 가드 유지
            return False, f"Instance {instance_id} is not registered in any ASG"

        asg_inst = asg_instances[0]
        lifecycle_state = asg_inst.get("LifecycleState")
        if lifecycle_state != "InService":
            return False, f"Instance {instance_id} is in ASG lifecycle state '{lifecycle_state}' (not InService)"

        return True, "InService"
    except Exception as e:
        logger.warning(f"Failed to check ASG instance status for {instance_id}: {e}")
        # 오류 발생 시 안전하게 준비 미완료로 처리 (Fail-closed)
        return False, f"ASG query error: {e}"


def is_instance_eip_ready(instance_id, expected_allocation_id=None):
    """
    인스턴스의 Primary ENI(eth0)에 Elastic IP(고정 EIP)가 정상 연결되어 있는지 검증합니다.
    Launch Template의 associate_public_ip_address=true로 인해 자동 할당된 임시 공인 IP는
    AllocationId가 없으므로 이를 배제하고, fck-nat가 고정 EIP를 associate 완료했는지 판정합니다.
    """
    if not instance_id:
        return False, "No instance ID"
    try:
        # describe_instances의 Association에는 AllocationId가 없어 ENI API로 조회한다.
        resp = ec2_client.describe_network_interfaces(
            Filters=[
                {"Name": "attachment.instance-id", "Values": [instance_id]},
                {"Name": "attachment.device-index", "Values": ["0"]},
            ]
        )
        for iface in resp.get("NetworkInterfaces", []):
            if iface.get("Attachment", {}).get("DeviceIndex") == 0:
                assoc = iface.get("Association", {})
                alloc_id = assoc.get("AllocationId")
                public_ip = assoc.get("PublicIp")

                if not alloc_id:
                    if public_ip:
                        return False, (
                            f"Instance {instance_id} eth0 has auto-assigned public IP ({public_ip}) "
                            f"but static EIP (AllocationId) is not associated yet"
                        )
                    return False, f"Instance {instance_id} eth0 has no public IP/EIP associated yet"

                if expected_allocation_id and alloc_id != expected_allocation_id:
                    return False, (
                        f"Instance {instance_id} eth0 EIP AllocationId '{alloc_id}' does not match "
                        f"expected static AllocationId '{expected_allocation_id}'"
                    )

                return True, f"Static EIP associated on eth0 (AllocationId: {alloc_id}, PublicIp: {public_ip})"

        return False, f"Instance {instance_id} has no eth0 (DeviceIndex 0) interface found"
    except Exception as e:
        logger.warning(f"Failed to check EIP status for {instance_id}: {e}")
        return False, f"EIP query error: {e}"


def is_floating_eni_ready(eni_id):
    """
    고정 Floating ENI가 인스턴스에 정상적으로 부착(attached)되어 있고,
    해당 인스턴스가 실제로 running 및 2/2 status check를 통과(healthy)했으며,
    ASG Lifecycle Hook이 완료되어 InService 상태이고 NAT/EIP가 준비되었는지 검증합니다.
    조기 페일백(Premature Failback)으로 인한 라우팅 블랙홀을 원천 차단합니다.
    반환값: (is_ready, instance_id, reason)
    """
    if not eni_id:
        return False, None, "Floating ENI ID is empty"
    try:
        resp = ec2_client.describe_network_interfaces(NetworkInterfaceIds=[eni_id])
        enis = resp.get("NetworkInterfaces", [])
        if not enis:
            return False, None, f"Network interface {eni_id} not found"

        eni = enis[0]
        status = eni.get("Status")
        attachment = eni.get("Attachment")

        if not attachment or attachment.get("Status") != "attached":
            return False, None, f"ENI {eni_id} status is '{status}', attachment status is not 'attached'"

        instance_id = attachment.get("InstanceId")
        if not instance_id:
            return False, None, f"ENI {eni_id} has no attached instance ID"

        # 1. 인스턴스 running 및 2/2 헬스체크 통과 여부 검증
        if not is_instance_healthy(instance_id):
            return False, instance_id, f"Attached instance {instance_id} is not fully healthy yet"

        # 2. ASG InService 여부 검증 (Pending:Wait 상태 등 Lifecycle Hook 진행 중 조기 페일백 원천 방지)
        asg_ready, asg_reason = is_instance_asg_inservice(instance_id)
        if not asg_ready:
            return False, instance_id, asg_reason

        # 3. NAT/EIP 바인딩 완료 여부 검증 (Primary ENI에 고정 EIP AllocationId 연결 확인)
        expected_alloc_id = None
        if eni_id == NAT_1_ENI_ID:
            expected_alloc_id = NAT_1_EIP_ALLOC_ID
        elif eni_id == NAT_2_ENI_ID:
            expected_alloc_id = NAT_2_EIP_ALLOC_ID

        eip_ready, eip_reason = is_instance_eip_ready(instance_id, expected_allocation_id=expected_alloc_id)
        if not eip_ready:
            return False, instance_id, eip_reason

        return True, instance_id, "Ready"
    except Exception as e:
        logger.error(f"Failed to check floating ENI {eni_id} readiness: {e}")
        return False, None, str(e)



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
    # EC2 running 직후에는 OS/fck-nat 초기화나 Floating ENI attach가 덜 끝났을 수 있으므로,
    # is_floating_eni_ready()가 True일 때만 Reconcile하고 아직 준비 전이면 기존 failover 라우트를 유지합니다.
    if state == "running":
        if is_nat_1:
            target_rtb = ROUTE_TABLE_A_ID
            fixed_floating_eni = NAT_1_ENI_ID
        else:
            target_rtb = ROUTE_TABLE_C_ID
            fixed_floating_eni = NAT_2_ENI_ID

        is_ready, attached_inst, reason = is_floating_eni_ready(fixed_floating_eni)
        if not is_ready:
            logger.info(
                f"⏳ [RECONCILIATION DEFERRED] {nat_name} ({instance_id}) is running but Floating ENI ({fixed_floating_eni}) "
                f"is not fully ready yet: {reason}. Keeping current route intact. "
                f"CloudWatch OK event will restore the route once ENI attach and 2/2 status checks pass."
            )
            return {
                "status": "DEFERRED",
                "reason": f"{nat_name} Floating ENI is not ready: {reason}",
                "instance_id": instance_id,
            }

        logger.info(
            f"🔄 [RECONCILIATION] {nat_name} ({instance_id}) is running and Floating ENI is healthy. "
            f"Reconciling Route Table {target_rtb} to Fixed Floating ENI {fixed_floating_eni}..."
        )
        result = update_route(target_rtb, fixed_floating_eni)
        return {
            "status": "RECONCILED",
            "instance_id": instance_id,
            "route_table_id": target_rtb,
            "eni_id": fixed_floating_eni,
            "detail": result,
        }

    # 2. 인스턴스 중지/종료 시 즉각 Failover
    elif state in ["stopped", "shutting-down", "terminated"]:
        logger.warning(
            f"🚨 [FAST FAILOVER] {nat_name} ({instance_id}) entered '{state}' state. Triggering failover..."
        )
        live_nat_1_eni = NAT_1_ENI_ID
        live_nat_2_eni = NAT_2_ENI_ID

        if is_nat_1:
            partner_id, is_api_error = get_partner_instance_id(is_nat_1=True)
            if is_api_error:
                reason = f"DescribeInstances query failed while checking partner NAT-2 ({NAT_2_TAG_NAME}) due to API error."
                logger.error(f"🚨 FAILOVER PAUSED: {reason}")
                return {
                    "statusCode": 503,
                    "status": "QUERY_FAILED_ABORTED",
                    "reason": reason,
                    "route_table_id": ROUTE_TABLE_A_ID,
                }

            partner_healthy = is_instance_healthy(partner_id) if partner_id else False
            # DUAL_FAILURE_ABORTED는 상대 NAT의 실제 health가 False이거나 인스턴스가 없을 때만 반환
            if not partner_healthy:
                reason = (
                    f"Partner NAT-2 ({partner_id or 'NOT_FOUND'}) is unhealthy or not running "
                    f"while NAT-1 entered '{state}'"
                )
                logger.critical(f"🚨🚨 DUAL NAT FAILURE DETECTED: {reason}")
                send_dual_failure_alert(ROUTE_TABLE_A_ID, instance_id, partner_id or "NONE", reason)
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
            partner_id, is_api_error = get_partner_instance_id(is_nat_1=False)
            if is_api_error:
                reason = f"DescribeInstances query failed while checking partner NAT-1 ({NAT_1_TAG_NAME}) due to API error."
                logger.error(f"🚨 FAILOVER PAUSED: {reason}")
                return {
                    "statusCode": 503,
                    "status": "QUERY_FAILED_ABORTED",
                    "reason": reason,
                    "route_table_id": ROUTE_TABLE_C_ID,
                }

            partner_healthy = is_instance_healthy(partner_id) if partner_id else False
            if not partner_healthy:
                reason = (
                    f"Partner NAT-1 ({partner_id or 'NOT_FOUND'}) is unhealthy or not running "
                    f"while NAT-2 entered '{state}'"
                )
                logger.critical(f"🚨🚨 DUAL NAT FAILURE DETECTED: {reason}")
                send_dual_failure_alert(ROUTE_TABLE_C_ID, instance_id, partner_id or "NONE", reason)
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


def reconcile_all_routes():
    """
    모든 프라이빗 라우팅 테이블(RTB-A, RTB-C)의 대상을 점검하여,
    이전에 DEFERRED되어 우회 경로에 남아있던 라우트를 정상화된 원래 Floating ENI로 안전하게 복구합니다.
    - RTB-A가 NAT-2(우회)를 가리키고 있는데 NAT-1이 2/2 healthy & ready이면 -> RTB-A를 NAT-1으로 페일백
    - RTB-C가 NAT-1(우회)를 가리키고 있는데 NAT-2가 2/2 healthy & ready이면 -> RTB-C를 NAT-2로 페일백
    """
    results = {}

    # 1. Route Table A 점검
    current_a = get_current_nat_eni(ROUTE_TABLE_A_ID)
    if current_a == NAT_2_ENI_ID:
        is_ready, inst_id, reason = is_floating_eni_ready(NAT_1_ENI_ID)
        if is_ready:
            logger.info(
                f"🔄 [PERIODIC RECONCILIATION] RTB-A is currently failed over to NAT-2, but NAT-1 ({inst_id}) "
                f"is now fully healthy and ready! Restoring RTB-A -> NAT-1 ENI ({NAT_1_ENI_ID})."
            )
            results["route_table_a"] = update_route(ROUTE_TABLE_A_ID, NAT_1_ENI_ID)
        else:
            logger.info(
                f"⏳ [PERIODIC RECONCILIATION] RTB-A remains failed over to NAT-2 because NAT-1 is not ready yet: {reason}."
            )
            results["route_table_a"] = {"status": "DEFERRED", "reason": reason}
    else:
        results["route_table_a"] = {"status": "HEALTHY", "current_eni": current_a}

    # 2. Route Table C 점검
    current_c = get_current_nat_eni(ROUTE_TABLE_C_ID)
    if current_c == NAT_1_ENI_ID:
        is_ready, inst_id, reason = is_floating_eni_ready(NAT_2_ENI_ID)
        if is_ready:
            logger.info(
                f"🔄 [PERIODIC RECONCILIATION] RTB-C is currently failed over to NAT-1, but NAT-2 ({inst_id}) "
                f"is now fully healthy and ready! Restoring RTB-C -> NAT-2 ENI ({NAT_2_ENI_ID})."
            )
            results["route_table_c"] = update_route(ROUTE_TABLE_C_ID, NAT_2_ENI_ID)
        else:
            logger.info(
                f"⏳ [PERIODIC RECONCILIATION] RTB-C remains failed over to NAT-1 because NAT-2 is not ready yet: {reason}."
            )
            results["route_table_c"] = {"status": "DEFERRED", "reason": reason}
    else:
        results["route_table_c"] = {"status": "HEALTHY", "current_eni": current_c}

    reconciled = any(
        isinstance(r, dict) and r.get("status") in ["UPDATED", "CREATED"]
        for r in results.values()
    )
    overall_status = "RECONCILED" if reconciled else "NOOP"
    return {"status": overall_status, "details": results}


def lambda_handler(event, context):
    """
    CloudWatch Alarm 및 EventBridge 이벤트를 처리합니다.
    - CloudWatch Alarm ALARM: NAT 인스턴스 장애 시 파트너 헬스체크 후 페일오버 (동시 장애 레이스 컨디션 방지)
    - CloudWatch Alarm OK: NAT 정상 복구 시 페일백
    - EventBridge EC2 state-change: NAT 신규 생성/재시작 시 최신 Live ENI로 Route Reconciliation
    - EventBridge Scheduled Event: 지연된 페일백(FAILBACK_DEFERRED)을 주기적으로 감지하여 정상 복구
    """
    logger.info(f"Received event: {json.dumps(event)}")

    # 0-1. EventBridge 주기적 Reconciliation (Scheduled Event) 또는 ASG Launch 성공 이벤트 확인
    if isinstance(event, dict) and (
        (event.get("source") == "aws.events" and event.get("detail-type") == "Scheduled Event")
        or (event.get("source") == "aws.autoscaling" and "Launch" in event.get("detail-type", ""))
    ):
        logger.info("🔄 Triggering periodic / lifecycle route reconciliation...")
        res = reconcile_all_routes()
        return {"statusCode": 200, "result": res}

    # 0-2. EventBridge EC2 State-change Notification (Reconciliation) 확인
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
        else:
            inst_name = get_instance_name_tag(target_instance)
            if inst_name == NAT_1_TAG_NAME:
                is_nat_1 = True
            elif inst_name == NAT_2_TAG_NAME:
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

    # 3. 고정 Floating ENI 적용 (Self-Healing ASG 아키텍처)
    live_nat_1_eni = NAT_1_ENI_ID
    live_nat_2_eni = NAT_2_ENI_ID

    # 4. 상태별 페일오버 및 페일백 분기
    if is_nat_1:
        if new_state == "ALARM":
            logger.info("🚨 NAT-1 FAILED: Checking partner (NAT-2) status before failover...")
            partner_id, is_api_error = get_partner_instance_id(is_nat_1=True)
            if is_api_error:
                reason = f"DescribeInstances query failed while checking partner NAT-2 ({NAT_2_TAG_NAME}) due to API error."
                logger.error(f"🚨 FAILOVER PAUSED: {reason}")
                return {
                    "statusCode": 503,
                    "status": "QUERY_FAILED_ABORTED",
                    "reason": reason,
                    "route_table_id": ROUTE_TABLE_A_ID,
                }

            partner_healthy = is_instance_healthy(partner_id) if partner_id else False

            # DUAL_FAILURE_ABORTED는 상대 NAT의 실제 health가 false이거나 인스턴스가 없을 때만 반환
            if not partner_healthy:
                reason = f"Partner NAT-2 ({partner_id or 'NOT_FOUND'}) health check failed (healthy={partner_healthy})"
                logger.critical(
                    f"🚨🚨 CRITICAL: DUAL NAT FAILURE DETECTED! {reason}. "
                    f"Both NAT instances are DOWN! "
                    f"Aborting failover to dead instance to avoid circular routing. Manual intervention required!"
                )
                send_dual_failure_alert(
                    route_table_id=ROUTE_TABLE_A_ID,
                    target_instance_id=target_instance or NAT_1_INSTANCE_ID or "NAT-1",
                    partner_instance_id=partner_id or "NONE",
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
            is_ready, attached_inst, reason = is_floating_eni_ready(live_nat_1_eni)
            if not is_ready:
                logger.warning(
                    f"⏳ [FAILBACK DEFERRED] NAT-1 alarm is OK, but Floating ENI ({live_nat_1_eni}) "
                    f"is not fully ready yet: {reason}. Keeping current failover route to prevent routing blackhole."
                )
                res = {
                    "status": "FAILBACK_DEFERRED",
                    "reason": reason,
                    "eni_id": live_nat_1_eni,
                    "instance_id": attached_inst,
                }
            else:
                logger.info("✅ NAT-1 RECOVERED & VERIFIED: Triggering Failback for Route Table A -> NAT-1 ENI")
                res = update_route(ROUTE_TABLE_A_ID, live_nat_1_eni)
        else:
            logger.info(f"NAT-1 entered state '{new_state}'. No action taken.")
            res = {"status": "IGNORED", "state": new_state}
    else:  # is_nat_2
        if new_state == "ALARM":
            logger.info("🚨 NAT-2 FAILED: Checking partner (NAT-1) status before failover...")
            partner_id, is_api_error = get_partner_instance_id(is_nat_1=False)
            if is_api_error:
                reason = f"DescribeInstances query failed while checking partner NAT-1 ({NAT_1_TAG_NAME}) due to API error."
                logger.error(f"🚨 FAILOVER PAUSED: {reason}")
                return {
                    "statusCode": 503,
                    "status": "QUERY_FAILED_ABORTED",
                    "reason": reason,
                    "route_table_id": ROUTE_TABLE_C_ID,
                }

            partner_healthy = is_instance_healthy(partner_id) if partner_id else False

            if not partner_healthy:
                reason = f"Partner NAT-1 ({partner_id or 'NOT_FOUND'}) health check failed (healthy={partner_healthy})"
                logger.critical(
                    f"🚨🚨 CRITICAL: DUAL NAT FAILURE DETECTED! {reason}. "
                    f"Both NAT instances are DOWN! "
                    f"Aborting failover to dead instance to avoid circular routing. Manual intervention required!"
                )
                send_dual_failure_alert(
                    route_table_id=ROUTE_TABLE_C_ID,
                    target_instance_id=target_instance or NAT_2_INSTANCE_ID or "NAT-2",
                    partner_instance_id=partner_id or "NONE",
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
            is_ready, attached_inst, reason = is_floating_eni_ready(live_nat_2_eni)
            if not is_ready:
                logger.warning(
                    f"⏳ [FAILBACK DEFERRED] NAT-2 alarm is OK, but Floating ENI ({live_nat_2_eni}) "
                    f"is not fully ready yet: {reason}. Keeping current failover route to prevent routing blackhole."
                )
                res = {
                    "status": "FAILBACK_DEFERRED",
                    "reason": reason,
                    "eni_id": live_nat_2_eni,
                    "instance_id": attached_inst,
                }
            else:
                logger.info("✅ NAT-2 RECOVERED & VERIFIED: Triggering Failback for Route Table C -> NAT-2 ENI")
                res = update_route(ROUTE_TABLE_C_ID, live_nat_2_eni)
        else:
            logger.info(f"NAT-2 entered state '{new_state}'. No action taken.")
            res = {"status": "IGNORED", "state": new_state}

    return {"statusCode": 200, "result": res}


