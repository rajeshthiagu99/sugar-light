"""Authenticated Google Play RTDN handler. Deploy behind verified Pub/Sub push."""
import base64, json
from fastapi import FastAPI, HTTPException, Request
from googleapiclient.discovery import build
app = FastAPI()
PACKAGE = "com.rajesht.breatheagain"
PRODUCT = "breathe_again_monthly"
entitlements: dict[str, str] = {}  # Replace with durable production DB.
@app.post("/rtdn")
async def rtdn(request: Request):
    envelope = await request.json()
    try:
        event = json.loads(base64.b64decode(envelope["message"]["data"]))
        notice = event["subscriptionNotification"]
        token, product = notice["purchaseToken"], notice["subscriptionId"]
    except Exception as exc:
        raise HTTPException(400, "Invalid RTDN envelope") from exc
    if product != PRODUCT: return {"ignored": True}
    purchase = build("androidpublisher", "v3", cache_discovery=False).purchases().subscriptionsv2().get(packageName=PACKAGE, token=token).execute()
    mapped = {
      "SUBSCRIPTION_STATE_ACTIVE": "active",
      "SUBSCRIPTION_STATE_IN_GRACE_PERIOD": "grace",
      "SUBSCRIPTION_STATE_ON_HOLD": "hold",
      "SUBSCRIPTION_STATE_CANCELED": "canceled",
      "SUBSCRIPTION_STATE_EXPIRED": "expired",
    }.get(purchase.get("subscriptionState"), "hold")
    account = purchase.get("externalAccountIdentifiers", {}).get("obfuscatedExternalAccountId")
    if account: entitlements[account] = mapped
    return {"ok": True, "state": mapped}
