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


def lambda_handler(event, context):
    """
    SNS 이벤트를 받아 각 레코드별로 Slack에 알림을 전송한다.
    SNS 메시지 내 AlarmName / NewStateValue / NewStateReason 필드를 파싱한다.
    """
    webhook_url = _get_webhook_url()

    for record in event.get("Records", []):
        try:
            sns_message = json.loads(record["Sns"]["Message"])
        except (KeyError, json.JSONDecodeError) as e:
            print(f"[WARN] SNS 메시지 파싱 실패: {e} / 원본: {record}")
            continue

        alarm_name = sns_message.get("AlarmName", "Unknown Alarm")
        new_state = sns_message.get("NewStateValue", "UNKNOWN")
        reason = sns_message.get("NewStateReason", "사유 없음")

        payload = _build_slack_payload(alarm_name, new_state, reason)
        data = json.dumps(payload).encode("utf-8")

        req = urllib.request.Request(
            webhook_url,
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                print(f"[OK] Slack 전송 완료: {alarm_name} / HTTP {resp.status}")
        except urllib.error.HTTPError as e:
            print(f"[ERROR] Slack HTTP 오류: {e.code} {e.reason}")
            raise
        except Exception as e:
            print(f"[ERROR] Slack 전송 실패: {e}")
            raise

    return {"statusCode": 200, "body": "알림 전송 완료"}
