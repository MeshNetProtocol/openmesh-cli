#!/usr/bin/env python3
"""
直接使用 gRPC 调用 Xray API 添加用户
手动构造 protobuf 消息，绕过 xray api adu 命令行工具
"""

import grpc
import sys
from google.protobuf import any_pb2
from google.protobuf.message import Message

# 手动定义 protobuf 消息结构
# 参考：https://github.com/XTLS/Xray-core/blob/main/app/proxyman/command/command.proto

def create_alter_inbound_request(inbound_tag, email, uuid, operation_type="add"):
    """
    手动构造 AlterInboundRequest

    message AlterInboundRequest {
        string tag = 1;
        xray.common.serial.TypedMessage operation = 2;
    }

    message AddUserOperation {
        xray.common.protocol.User user = 1;
    }
    """

    # 创建 gRPC channel
    channel = grpc.insecure_channel('127.0.0.1:10085')

    try:
        # 由于我们没有生成的 protobuf 代码，我们需要手动构造字节
        # 这里使用 grpc 的通用调用方式

        # 构造请求
        # 字段 1: tag (string)
        # 字段 2: operation (TypedMessage)

        # TypedMessage 包含:
        # - type (string): 消息类型 URL
        # - value (bytes): 序列化的消息

        # AddUserOperation 包含:
        # - user (User)

        # User 包含:
        # - email (string)
        # - account (Account)

        # Account (VLESS) 包含:
        # - id (string): UUID

        print(f"尝试通过 gRPC 添加用户: {email}")
        print(f"Inbound Tag: {inbound_tag}")
        print(f"UUID: {uuid}")

        # 使用 grpc 的通用调用
        # 服务路径: /xray.app.proxyman.command.HandlerService/AlterInbound

        # 手动构造 protobuf 字节
        # 这需要正确的 protobuf 编码

        # 由于没有生成的代码，我们使用原始字节构造
        # Tag 字段 (field 1, wire type 2 = length-delimited)
        tag_bytes = inbound_tag.encode('utf-8')
        tag_field = bytes([0x0a]) + bytes([len(tag_bytes)]) + tag_bytes

        # Operation 字段 (field 2, wire type 2 = length-delimited)
        # 这是一个 TypedMessage，包含 type 和 value

        # 构造 AddUserOperation
        # User 字段 (field 1)
        # email 字段 (field 1 in User)
        email_bytes = email.encode('utf-8')
        email_field = bytes([0x0a]) + bytes([len(email_bytes)]) + email_bytes

        # account 字段 (field 2 in User)
        # 这是一个 Any 类型，包含 VLESS Account
        # VLESS Account 的 id 字段 (field 1)
        uuid_bytes = uuid.encode('utf-8')
        uuid_field = bytes([0x0a]) + bytes([len(uuid_bytes)]) + uuid_bytes

        # 组装 VLESS Account
        vless_account = uuid_field

        # 组装 Any (account)
        # type_url 字段 (field 1)
        type_url = "type.googleapis.com/xray.proxy.vless.Account"
        type_url_bytes = type_url.encode('utf-8')
        type_url_field = bytes([0x0a]) + bytes([len(type_url_bytes)]) + type_url_bytes

        # value 字段 (field 2)
        value_field = bytes([0x12]) + bytes([len(vless_account)]) + vless_account

        account_any = type_url_field + value_field
        account_field = bytes([0x12]) + bytes([len(account_any)]) + account_any

        # 组装 User
        user_message = email_field + account_field
        user_field = bytes([0x0a]) + bytes([len(user_message)]) + user_message

        # 组装 AddUserOperation
        add_user_op = user_field

        # 组装 TypedMessage (operation)
        # type 字段 (field 1)
        op_type_url = "type.googleapis.com/xray.app.proxyman.command.AddUserOperation"
        op_type_url_bytes = op_type_url.encode('utf-8')
        op_type_field = bytes([0x0a]) + bytes([len(op_type_url_bytes)]) + op_type_url_bytes

        # value 字段 (field 2)
        op_value_field = bytes([0x12]) + bytes([len(add_user_op)]) + add_user_op

        operation_message = op_type_field + op_value_field
        operation_field = bytes([0x12]) + bytes([len(operation_message)]) + operation_message

        # 组装完整的 AlterInboundRequest
        request_bytes = tag_field + operation_field

        print(f"\n构造的请求字节长度: {len(request_bytes)}")
        print(f"请求字节 (hex): {request_bytes.hex()}")

        # 调用 gRPC
        response_bytes = channel.unary_unary(
            '/xray.app.proxyman.command.HandlerService/AlterInbound',
            request_serializer=lambda x: x,
            response_deserializer=lambda x: x
        )(request_bytes)

        print(f"\n✅ 成功！响应字节长度: {len(response_bytes)}")
        print(f"响应字节 (hex): {response_bytes.hex()}")

        return True

    except grpc.RpcError as e:
        print(f"\n❌ gRPC 错误:")
        print(f"  状态码: {e.code()}")
        print(f"  详情: {e.details()}")
        return False
    except Exception as e:
        print(f"\n❌ 错误: {e}")
        import traceback
        traceback.print_exc()
        return False
    finally:
        channel.close()

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: python3 grpc_add_user.py <inbound_tag> <email> <uuid>")
        print("Example: python3 grpc_add_user.py vless-in user@test.com 11111111-1111-1111-1111-111111111111")
        sys.exit(1)

    result = create_alter_inbound_request(sys.argv[1], sys.argv[2], sys.argv[3])
    sys.exit(0 if result else 1)
