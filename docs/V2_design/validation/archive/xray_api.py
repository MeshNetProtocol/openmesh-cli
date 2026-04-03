#!/usr/bin/env python3
"""
测试 Xray gRPC API RemoveUser 是否能阻止新连接
"""

import grpc
from xray_rpc.app.proxyman.command import command_pb2, command_pb2_grpc
from xray_rpc.common.protocol import user_pb2
from xray_rpc.common.serial import typed_message_pb2
from xray_rpc.proxy.vmess import account_pb2

def add_user(email, uuid):
    channel = grpc.insecure_channel("127.0.0.1:10085")
    stub = command_pb2_grpc.HandlerServiceStub(channel)

    vmess_account = account_pb2.Account(id=uuid)
    typed_msg = typed_message_pb2.TypedMessage()
    typed_msg.type = "xray.proxy.vmess.Account"
    typed_msg.value = vmess_account.SerializeToString()

    user = user_pb2.User(email=email, account=typed_msg)
    add_op = command_pb2.AddUserOperation(user=user)

    operation = typed_message_pb2.TypedMessage()
    operation.type = "xray.app.proxyman.command.AddUserOperation"
    operation.value = add_op.SerializeToString()

    request = command_pb2.AlterInboundRequest(tag="vmess-in", operation=operation)
    stub.AlterInbound(request)
    print(f"✅ 添加用户: {email}")

def remove_user(email):
    channel = grpc.insecure_channel("127.0.0.1:10085")
    stub = command_pb2_grpc.HandlerServiceStub(channel)

    remove_op = command_pb2.RemoveUserOperation(email=email)
    operation = typed_message_pb2.TypedMessage()
    operation.type = "xray.app.proxyman.command.RemoveUserOperation"
    operation.value = remove_op.SerializeToString()

    request = command_pb2.AlterInboundRequest(tag="vmess-in", operation=operation)
    stub.AlterInbound(request)
    print(f"✅ 删除用户: {email}")

if __name__ == "__main__":
    import sys
    if len(sys.argv) < 2:
        print("用法: python3 xray_api.py add <email> <uuid>")
        print("      python3 xray_api.py remove <email>")
        sys.exit(1)

    if sys.argv[1] == "add":
        add_user(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == "remove":
        remove_user(sys.argv[2])
