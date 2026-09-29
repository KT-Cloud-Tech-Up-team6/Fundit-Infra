"""
Slack Notifier Lambda
- SNS 트리거로 CloudWatch 알람 메시지를 수신
- AWS Secrets Manager에서 Slack Webhook URL 조회
- Slack에 포맷된 메시지 전송
"""
import json
import os
import urllib.request
import urllib.error
import boto3

# Secrets Manager 클라이언트는 콜드 스타트에 한 번만 생성
_secrets_client = boto3.client("secretsmanager")
_cached_webhook_url: str | None = None


def _get_webhook_url() -> str:
    """Slack Webhook URL을 Secrets Manager에서 조회 (Lambda 재사용 시 캐시 활용)."""
    global _cached_webhook_url
    if _cached_webhook_url:
        return _cached_webhook_url

    secret_name = os.environ["SLACK_SECRET_NAME"]
    response = _secrets_client.get_secret_value(SecretId=secret_name)
    secret = json.loads(response["SecretString"])
    _cached_webhook_url = secret["webhook_url"]
    return _cached_webhook_url


def _build_slack_payload(alarm_name: str, new_state: str, reason: str) -> dict:
    """CloudWatch 알람 정보를 Slack 메시지 페이로드로 변환."""
    emoji_map = {"ALARM": "🔴", "OK": "✅", "INSUFFICIENT_DATA": "🟡"}
    color_map = {"ALARM": "danger", "OK": "good", "INSUFFICIENT_DATA": "warning"}

    emoji = emoji_map.get(new_state, "❓")
    color = color_map.get(new_state, "#808080")

    return {
        "attachments": [
            {
                "color": color,
                "title": f"{emoji} [{new_state}] {alarm_name}",
                "text": reason,
                "footer": "AWS CloudWatch | Fundit Dev",
                "mrkdwn_in": ["text"],
            }
        ]
    }


def _build_plain_message_payload(subject: str, message: str) -> dict:
    """
    CloudWatch JSON이 아닌 일반 문자열 SNS 메시지(예: NAT 이중 장애 DUAL_FAILURE_ABORTED)를
    Slack 메시지 페이로드로 변환.
    """
    critical_keywords = ["CRITICAL", "ALERT", "FAIL", "ABORT", "ERROR"]
    full_text = f"{subject} {message}".upper()
    is_critical = any(kw in full_text for kw in critical_keywords)

    emoji = "🚨" if is_critical else "ℹ️"
    color = "danger" if is_critical else "#3AA3E3"
    title = f"{emoji} {subject}" if subject else f"{emoji} AWS SNS Notification"

    return {
        "attachments": [
            {
                "color": color,
                "title": title,
                "text": message,
                "footer": "AWS SNS | Fundit Dev",
                "mrkdwn_in": ["text"],
            }
        ]
    }


def lambda_handler(event, context):
    """
    SNS 이벤트를 받아 각 레코드별로 Slack에 알림을 전송한다.
    - CloudWatch 알람 JSON: AlarmName / NewStateValue / NewStateReason 파싱
    - 일반 텍스트 SNS 메시지: Subject 및 Message 원문을 Slack으로 전송 (NAT 이중 장애 등 유실 방지)
    """
    webhook_url = _get_webhook_url()

    for record in event.get("Records", []):
        sns_record = record.get("Sns", {})
        raw_message = sns_record.get("Message", "")
        subject = sns_record.get("Subject", "")

        try:
            sns_message = json.loads(raw_message)
        except (TypeError, json.JSONDecodeError):
            sns_message = None

        if isinstance(sns_message, dict) and "AlarmName" in sns_message:
            # CloudWatch Alarm 포맷
            alarm_name = sns_message.get("AlarmName", "Unknown Alarm")
            new_state = sns_message.get("NewStateValue", "UNKNOWN")
            reason = sns_message.get("NewStateReason", "사유 없음")
            payload = _build_slack_payload(alarm_name, new_state, reason)
            log_title = f"{alarm_name} ({new_state})"
        else:
            # 일반 텍스트 SNS 메시지 (예: NAT failover.py의 send_dual_failure_alert)
            payload = _build_plain_message_payload(subject, raw_message)
            log_title = subject or "Plain SNS Message"

        data = json.dumps(payload).encode("utf-8")

        req = urllib.request.Request(
            webhook_url,
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                print(f"[OK] Slack 전송 완료: {log_title} / HTTP {resp.status}")
        except urllib.error.HTTPError as e:
            print(f"[ERROR] Slack HTTP 오류: {e.code} {e.reason}")
            raise
        except Exception as e:
            print(f"[ERROR] Slack 전송 실패: {e}")
            raise

    return {"statusCode": 200, "body": "알림 전송 완료"}

