#!/usr/bin/env python3
"""
使用 xtlsapi 库调用 Xray gRPC API 添加用户
"""

import sys
from xtlsapi import XrayClient

def add_user_with_xtlsapi(inbound_tag, email, uuid):
    """使用 xtlsapi 添加用户"""

    try:
        # 连接到 Xray API
        client = XrayClient('127.0.0.1', 10085)

        print(f"尝试添加用户: {email}")
        print(f"Inbound Tag: {inbound_tag}")
        print(f"UUID: {uuid}")

        # 添加用户 (使用 add_client 方法)
        result = client.add_client(
            inbound_tag=inbound_tag,
            user_id_or_password=uuid,
            email=email,
            protocol='vless',
            flow=''  # VLESS 不需要 flow，设置为空字符串
        )

        print(f"\n✅ 成功添加用户！")
        print(f"结果: {result}")

        return True

    except Exception as e:
        print(f"\n❌ 错误: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: python3 test_xtlsapi.py <inbound_tag> <email> <uuid>")
        print("Example: python3 test_xtlsapi.py vless-in user@test.com 11111111-1111-1111-1111-111111111111")
        sys.exit(1)

    result = add_user_with_xtlsapi(sys.argv[1], sys.argv[2], sys.argv[3])
    sys.exit(0 if result else 1)
