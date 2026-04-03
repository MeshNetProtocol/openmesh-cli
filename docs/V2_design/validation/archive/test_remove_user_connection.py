#!/usr/bin/env python3
"""
验证 RemoveUser 后新连接是否会被拒绝的测试脚本

测试流程：
1. 添加测试用户
2. 使用 VMess 客户端建立连接并测试（应该成功）
3. 删除测试用户
4. 完全停止客户端，等待连接关闭
5. 重新启动客户端并尝试新连接（应该失败）
"""

import sys
import time
import subprocess
import json
import tempfile
import os
from xray_api import add_user, remove_user

# 测试配置
TEST_EMAIL = "test-validation@example.com"
TEST_UUID = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
SERVER_HOST = "127.0.0.1"
SERVER_PORT = 10086
SOCKS_PORT = 1080

def create_client_config():
    """生成 Xray 客户端配置"""
    config = {
        "log": {
            "loglevel": "warning"
        },
        "inbounds": [{
            "port": SOCKS_PORT,
            "protocol": "socks",
            "settings": {
                "udp": True
            }
        }],
        "outbounds": [{
            "protocol": "vmess",
            "settings": {
                "vnext": [{
                    "address": SERVER_HOST,
                    "port": SERVER_PORT,
                    "users": [{
                        "id": TEST_UUID,
                        "email": TEST_EMAIL,
                        "security": "auto"
                    }]
                }]
            }
        }]
    }

    # 创建临时配置文件
    fd, path = tempfile.mkstemp(suffix='.json', prefix='xray_client_')
    with os.fdopen(fd, 'w') as f:
        json.dump(config, f, indent=2)

    return path

def test_connection(config_path, description):
    """
    测试连接
    返回: (success: bool, client_process: subprocess.Popen or None)
    """
    print(f"\n🔍 测试: {description}")

    # 启动 Xray 客户端
    try:
        client = subprocess.Popen(
            ['xray', '-c', config_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )

        # 等待客户端启动
        print("   等待客户端启动...")
        time.sleep(3)

        # 测试连接 - 通过 SOCKS5 代理访问网站
        print("   尝试通过代理连接...")
        result = subprocess.run(
            ['curl', '-x', f'socks5://127.0.0.1:{SOCKS_PORT}',
             '-m', '10', '--silent', '--head', 'http://www.google.com'],
            capture_output=True,
            timeout=15
        )

        success = result.returncode == 0

        if success:
            print("   ✅ 连接成功")
        else:
            print("   ❌ 连接失败")
            stderr = result.stderr.decode('utf-8', errors='ignore')
            if stderr:
                print(f"   错误信息: {stderr[:200]}")

        return success, client

    except subprocess.TimeoutExpired:
        print("   ❌ 连接超时")
        return False, client
    except Exception as e:
        print(f"   ❌ 测试出错: {e}")
        return False, None

def stop_client(client):
    """停止客户端进程"""
    if client:
        try:
            client.terminate()
            client.wait(timeout=5)
        except:
            client.kill()
            client.wait()

def main():
    print("=" * 60)
    print("RemoveUser 新连接阻止验证测试")
    print("=" * 60)

    config_path = None

    try:
        # 生成客户端配置
        print("\n📝 生成客户端配置...")
        config_path = create_client_config()
        print(f"   配置文件: {config_path}")

        # 步骤 1: 添加用户
        print("\n" + "=" * 60)
        print("步骤 1: 添加测试用户")
        print("=" * 60)
        add_user(TEST_EMAIL, TEST_UUID)
        time.sleep(1)

        # 步骤 2: 测试初始连接（应该成功）
        print("\n" + "=" * 60)
        print("步骤 2: 测试初始连接（预期：成功）")
        print("=" * 60)
        success, client = test_connection(config_path, "用户添加后的连接")

        if not success:
            print("\n❌ 测试失败：初始连接应该成功但失败了")
            print("可能的原因：")
            print("  - Xray 服务端未运行")
            print("  - 服务端配置不正确")
            print("  - 网络连接问题")
            stop_client(client)
            return 1

        # 停止客户端
        print("\n   停止客户端...")
        stop_client(client)
        time.sleep(2)

        # 步骤 3: 删除用户
        print("\n" + "=" * 60)
        print("步骤 3: 删除测试用户")
        print("=" * 60)
        remove_user(TEST_EMAIL)

        # 步骤 4: 等待连接完全关闭
        print("\n" + "=" * 60)
        print("步骤 4: 等待连接完全关闭")
        print("=" * 60)
        print("   等待 5 秒...")
        time.sleep(5)

        # 步骤 5: 测试新连接（应该失败）
        print("\n" + "=" * 60)
        print("步骤 5: 测试新连接（预期：失败）")
        print("=" * 60)
        success, client = test_connection(config_path, "用户删除后的新连接")

        # 停止客户端
        stop_client(client)

        # 验证结果
        print("\n" + "=" * 60)
        print("测试结果")
        print("=" * 60)

        if success:
            print("\n❌ 测试失败：RemoveUser 后新连接仍然成功！")
            print("\n这意味着：")
            print("  - RemoveUser 没有阻止新连接")
            print("  - 可能需要重启 Xray 服务端才能生效")
            print("  - 或者 Xray 的行为与预期不符")
            return 1
        else:
            print("\n✅ 测试通过：RemoveUser 成功阻止了新连接！")
            print("\n结论：")
            print("  - RemoveUser 操作能够阻止新连接")
            print("  - 已有连接不会被断开（这是预期行为）")
            print("  - 满足我们的需求：无需重启服务端即可禁用用户")
            return 0

    except KeyboardInterrupt:
        print("\n\n⚠️  测试被用户中断")
        return 130
    except Exception as e:
        print(f"\n\n❌ 测试出错: {e}")
        import traceback
        traceback.print_exc()
        return 1
    finally:
        # 清理临时文件
        if config_path and os.path.exists(config_path):
            try:
                os.unlink(config_path)
                print(f"\n🧹 清理临时文件: {config_path}")
            except:
                pass

if __name__ == "__main__":
    sys.exit(main())
