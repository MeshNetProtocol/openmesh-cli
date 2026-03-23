#!/usr/bin/env python3
"""
流量采集服务 - node-a
定期模拟流量数据并上报到记账服务
"""

import time
import random
import requests
import json
from datetime import datetime

# 配置
NODE_ID = "node_c"
METERING_SERVICE_URL = "http://127.0.0.1:9000"
REPORT_INTERVAL = 10  # 秒
USERS = ["alice", "bob", "charlie"]

# 流量缓存（记录上次上报的累计值）
traffic_cache = {user: {"upload": 0, "download": 0} for user in USERS}


def simulate_traffic(user_id):
    """模拟用户流量增量（字节）"""
    # 随机生成流量增量：上传 0-100KB，下载 0-500KB
    upload_delta = random.randint(0, 102400)
    download_delta = random.randint(0, 512000)
    return upload_delta, download_delta


def report_traffic(node_id, user_id, upload_bytes, download_bytes):
    """上报流量到记账服务"""
    url = f"{METERING_SERVICE_URL}/api/v1/metering/report"
    payload = {
        "node_id": node_id,
        "user_id": user_id,
        "upload_bytes": upload_bytes,
        "download_bytes": download_bytes
    }

    try:
        response = requests.post(url, json=payload, timeout=5)
        response.raise_for_status()
        result = response.json()
        return result
    except requests.exceptions.RequestException as e:
        print(f"❌ 上报失败: {e}")
        return None


def main():
    print(f"🚀 启动流量采集服务 - {NODE_ID}")
    print(f"   上报间隔: {REPORT_INTERVAL} 秒")
    print(f"   记账服务: {METERING_SERVICE_URL}")
    print(f"   监控用户: {', '.join(USERS)}")
    print()

    cycle = 0

    while True:
        cycle += 1
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp}] 周期 #{cycle}")

        for user_id in USERS:
            # 模拟流量增量
            upload_delta, download_delta = simulate_traffic(user_id)

            # 只有当有流量时才上报
            if upload_delta > 0 or download_delta > 0:
                print(f"  📊 {user_id}: ↑ {upload_delta/1024:.1f}KB ↓ {download_delta/1024:.1f}KB", end=" ")

                # 上报到记账服务
                result = report_traffic(NODE_ID, user_id, upload_delta, download_delta)

                if result:
                    status = result.get("status")
                    action = result.get("action")
                    remaining = result.get("remaining", 0)
                    remaining_mb = remaining / 1024 / 1024

                    if status == "ok":
                        print(f"✅ 剩余: {remaining_mb:.1f}MB")
                    elif status == "insufficient":
                        print(f"⚠️  流量不足! 剩余: {remaining_mb:.1f}MB [已阻断]")
                    else:
                        print(f"❓ 未知状态: {status}")
                else:
                    print("❌ 上报失败")

        print()
        time.sleep(REPORT_INTERVAL)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n👋 流量采集服务已停止")
