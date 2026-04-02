#!/usr/bin/env python3
"""
EVM 地址到 UUID 映射工具
实现 EVM 地址与 UUID v5 之间的双向转换
"""

import uuid
import json
import os
from pathlib import Path


class UUIDMapper:
    """EVM 地址与 UUID 的映射工具"""

    def __init__(self, allowed_ids_path=None):
        """
        初始化映射工具

        Args:
            allowed_ids_path: allowed_ids.json 文件路径,默认为相对路径
        """
        if allowed_ids_path is None:
            # 默认路径:相对于脚本所在目录的上级目录
            script_dir = Path(__file__).parent
            allowed_ids_path = script_dir.parent / "allowed_ids.json"

        self.allowed_ids_path = Path(allowed_ids_path)
        self.allowed_addresses = self._load_allowed_ids()

    def _load_allowed_ids(self):
        """从配置文件加载允许的地址列表"""
        if not self.allowed_ids_path.exists():
            return []

        try:
            with open(self.allowed_ids_path, 'r') as f:
                data = json.load(f)
                return data.get('allowed_ids', [])
        except (json.JSONDecodeError, IOError) as e:
            print(f"警告: 无法加载 allowed_ids.json: {e}")
            return []

    def evm_to_uuid(self, evm_address):
        """
        将 EVM 地址转换为 UUID v5

        Args:
            evm_address: EVM 地址字符串

        Returns:
            UUID 字符串
        """
        # 转换为小写并去除可能的空格
        evm_address = evm_address.lower().strip()

        # 验证格式
        if not evm_address.startswith('0x') or len(evm_address) != 42:
            raise ValueError(f"无效的 EVM 地址格式: {evm_address}")

        # 使用 UUID v5 和 NAMESPACE_DNS 生成 UUID
        return str(uuid.uuid5(uuid.NAMESPACE_DNS, evm_address))

    def uuid_to_evm(self, target_uuid):
        """
        反向查找: 从 UUID 查找对应的 EVM 地址

        Args:
            target_uuid: 目标 UUID 字符串

        Returns:
            匹配的 EVM 地址,如果未找到则返回 None
        """
        target_uuid = target_uuid.lower().strip()

        # 在已知地址列表中查找
        for evm_address in self.allowed_addresses:
            if self.evm_to_uuid(evm_address) == target_uuid:
                return evm_address

        return None


def main():
    """命令行接口"""
    import sys

    mapper = UUIDMapper()

    # 测试用例
    test_addresses = {
        'client_a': '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'client_b': '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        'client_c': '0xcccccccccccccccccccccccccccccccccccccccc'
    }

    print("=== EVM 地址到 UUID 映射工具 ===\n")

    # 正向转换测试
    print("1. 正向转换测试 (EVM → UUID):")
    print("-" * 60)
    uuid_map = {}
    for name, address in test_addresses.items():
        generated_uuid = mapper.evm_to_uuid(address)
        uuid_map[name] = generated_uuid
        print(f"{name}: {address}")
        print(f"  → UUID: {generated_uuid}")
        print()

    # 一致性测试
    print("\n2. 一致性测试 (同一地址多次转换):")
    print("-" * 60)
    test_addr = test_addresses['client_a']
    uuid1 = mapper.evm_to_uuid(test_addr)
    uuid2 = mapper.evm_to_uuid(test_addr)
    print(f"地址: {test_addr}")
    print(f"第一次: {uuid1}")
    print(f"第二次: {uuid2}")
    print(f"结果: {'✓ 一致' if uuid1 == uuid2 else '✗ 不一致'}")

    # 唯一性测试
    print("\n3. 唯一性测试 (不同地址生成不同 UUID):")
    print("-" * 60)
    uuids = list(uuid_map.values())
    unique_uuids = set(uuids)
    print(f"生成的 UUID 数量: {len(uuids)}")
    print(f"唯一 UUID 数量: {len(unique_uuids)}")
    print(f"结果: {'✓ 全部唯一' if len(uuids) == len(unique_uuids) else '✗ 存在重复'}")

    # 反向查找测试
    print("\n4. 反向查找测试 (UUID → EVM):")
    print("-" * 60)
    for name, generated_uuid in uuid_map.items():
        found_address = mapper.uuid_to_evm(generated_uuid)
        expected_address = test_addresses[name]
        in_list = expected_address in mapper.allowed_addresses

        print(f"{name} UUID: {generated_uuid}")
        print(f"  期望地址: {expected_address}")
        print(f"  在列表中: {in_list}")
        print(f"  查找结果: {found_address if found_address else '未找到'}")

        if in_list:
            print(f"  状态: {'✓ 正确匹配' if found_address == expected_address else '✗ 匹配失败'}")
        else:
            print(f"  状态: {'✓ 正确返回 None' if found_address is None else '✗ 不应找到'}")
        print()

    print("\n=== 测试完成 ===")


if __name__ == '__main__':
    main()
