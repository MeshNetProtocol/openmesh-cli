package openmesh

// IOpenMesh 定义了 OpenMesh 的接口
type IOpenMesh interface {
    // 初始化应用
    InitApp(config []byte) error
    
    // 生成助记词
    GenerateMnemonic() ([]byte, error)
}

// NewIOpenMesh 创建一个新的 IOpenMesh 实现实例
func NewIOpenMesh() IOpenMesh {
    return &OpenMesh{}
}