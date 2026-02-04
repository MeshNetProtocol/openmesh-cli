package openmesh

import (
	"fmt"
	"sync"
	"time"
)

// MemoryOptimizedAppLib 是内存优化的版本
type MemoryOptimizedAppLib struct {
	config      []byte
	configMutex sync.RWMutex
	lastCleanup time.Time
	lastUsed    time.Time
	
	// 内存使用统计
	totalAllocated int64
	maxMemoryUsage int64
}

// NewMemoryOptimizedLib 创建内存优化的库实例
func NewMemoryOptimizedLib() *MemoryOptimizedAppLib {
	lib := &MemoryOptimizedAppLib{
		lastCleanup: time.Now(),
		lastUsed:    time.Now(),
	}
	
	// 启动内存监控
	go lib.memoryMonitor()
	return lib
}

func (a *MemoryOptimizedAppLib) InitApp(config []byte) error {
	a.configMutex.Lock()
	defer a.configMutex.Unlock()
	
	// 严格的内存限制
	if len(config) > 5*1024*1024 { // 5MB限制
		return fmt.Errorf("配置数据超过5MB限制")
	}
	
	// 先释放旧配置
	if a.config != nil {
		a.totalAllocated -= int64(len(a.config))
		a.config = nil
	}
	
	// 分配新配置
	a.config = make([]byte, len(config))
	copy(a.config, config)
	a.totalAllocated += int64(len(config))
	a.lastUsed = time.Now()
	
	// 更新最大内存使用
	if a.totalAllocated > a.maxMemoryUsage {
		a.maxMemoryUsage = a.totalAllocated
	}
	
	return nil
}

// 内存监控goroutine
func (a *MemoryOptimizedAppLib) memoryMonitor() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	
	for range ticker.C {
		a.performMemoryCheck()
	}
}

func (a *MemoryOptimizedAppLib) performMemoryCheck() {
	a.configMutex.Lock()
	defer a.configMutex.Unlock()
	
	now := time.Now()
	
	// 如果配置数据超过30分钟未使用，清理内存
	if now.Sub(a.lastUsed) > 30*time.Minute && len(a.config) > 0 {
		a.totalAllocated -= int64(len(a.config))
		a.config = nil
		a.lastCleanup = now
	}
	
	// 如果总内存使用超过10MB，强制清理
	if a.totalAllocated > 10*1024*1024 {
		a.forceCleanup()
	}
}

func (a *MemoryOptimizedAppLib) forceCleanup() {
	if a.config != nil {
		a.totalAllocated -= int64(len(a.config))
		a.config = nil
	}
	a.lastCleanup = time.Now()
}

// GetMemoryStats 返回内存使用统计
func (a *MemoryOptimizedAppLib) GetMemoryStats() map[string]interface{} {
	a.configMutex.RLock()
	defer a.configMutex.RUnlock()
	
	return map[string]interface{}{
		"current_usage":    a.totalAllocated,
		"max_usage":        a.maxMemoryUsage,
		"config_size":      len(a.config),
		"last_cleanup_ago": time.Since(a.lastCleanup).Seconds(),
		"last_used_ago":    time.Since(a.lastUsed).Seconds(),
	}
}