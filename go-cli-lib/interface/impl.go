package openmesh

import (
	"crypto/rand"
	"errors"
	"strings"
)

// OpenMesh 结构体实现 IOpenMesh 接口
type OpenMesh struct {
	config []byte
}

// NewOpenMesh 创建一个新的 OpenMesh 实例
func NewOpenMesh() *OpenMesh {
	return &OpenMesh{}
}

// InitApp 初始化应用
func (o *OpenMesh) InitApp(config []byte) error {
	o.config = make([]byte, len(config))
	copy(o.config, config)
	// 这里可以实现初始化逻辑
	return nil
}

// GenerateMnemonic 生成助记词
func (o *OpenMesh) GenerateMnemonic() ([]byte, error) {
	// 这里实现助记词生成逻辑
	// 为了演示目的，我们生成一个简单的助记词
	words := make([]string, 12)
	for i := range words {
		// 生成随机数据并转换为单词
		buf := make([]byte, 4)
		_, err := rand.Read(buf)
		if err != nil {
			return nil, errors.New("failed to generate random data")
		}
		
		// 将随机数据转换为简单的单词表示
		word := strings.ToLower(strings.ReplaceAll(
			string([]byte{
				'a' + (buf[0]%26),
				'b' + (buf[1]%26),
				'c' + (buf[2]%26),
				'd' + (buf[3]%26),
			}), "'", ""))
		words[i] = word
	}
	
	mnemonic := strings.Join(words, " ")
	return []byte(mnemonic), nil
}