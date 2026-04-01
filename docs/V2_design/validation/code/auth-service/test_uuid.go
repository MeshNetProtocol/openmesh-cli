package main

import (
	"crypto/sha1"
	"encoding/binary"
	"fmt"
	"strings"
)

// evmToUUID 将 EVM 地址转换为 UUID v5
func evmToUUID(evmAddress string) string {
	// NAMESPACE_DNS 的字节表示
	namespace := []byte{
		0x6b, 0xa7, 0xb8, 0x10,
		0x9d, 0xad,
		0x11, 0xd1,
		0x80, 0xb4,
		0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
	}

	// 转换为小写
	evmAddress = strings.ToLower(evmAddress)

	// 计算 SHA-1
	h := sha1.New()
	h.Write(namespace)
	h.Write([]byte(evmAddress))
	hash := h.Sum(nil)

	// 设置版本位 (version 5)
	hash[6] = (hash[6] & 0x0f) | 0x50

	// 设置变体位
	hash[8] = (hash[8] & 0x3f) | 0x80

	// 格式化为 UUID 字符串
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x",
		binary.BigEndian.Uint32(hash[0:4]),
		binary.BigEndian.Uint16(hash[4:6]),
		binary.BigEndian.Uint16(hash[6:8]),
		binary.BigEndian.Uint16(hash[8:10]),
		hash[10:16])
}

func main() {
	testAddresses := map[string]string{
		"client_a": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		"client_b": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
		"client_c": "0xcccccccccccccccccccccccccccccccccccccccc",
	}

	expectedUUIDs := map[string]string{
		"client_a": "d3507f8a-d4eb-541a-a231-929c6237eee5",
		"client_b": "b5001757-5cd5-56f9-b9ae-6168583ce15a",
		"client_c": "5d6feeaf-3d34-589c-a21d-795a2f9d99af",
	}

	fmt.Println("=== UUID 算法一致性测试 ===\n")

	allMatch := true
	for name, address := range testAddresses {
		generated := evmToUUID(address)
		expected := expectedUUIDs[name]
		match := generated == expected

		fmt.Printf("%s: %s\n", name, address)
		fmt.Printf("  Go 生成:     %s\n", generated)
		fmt.Printf("  Python 期望: %s\n", expected)
		fmt.Printf("  结果: %s\n\n", map[bool]string{true: "✓ 一致", false: "✗ 不一致"}[match])

		if !match {
			allMatch = false
		}
	}

	if allMatch {
		fmt.Println("=== 所有测试通过 ===")
	} else {
		fmt.Println("=== 测试失败 ===")
	}
}
