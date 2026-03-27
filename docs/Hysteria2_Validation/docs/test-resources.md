# 测试资源 URL

**用途**: Phase 0.2 流量统计准确度测试

**更新日期**: 2026-03-24

---

## 百度图片测试 URL

这些 URL 用于测试不同文件大小的流量统计准确度。通过 HTTPS 代理访问，可以验证流量统计的准确性。

### URL 列表

1. **119KB 图片**
   ```
   https://gips3.baidu.com/it/u=1821127123,1149655687&fm=3028&app=3028&f=JPEG&fmt=auto?w=720&h=1280
   ```
   - 实际文件大小: ~121,870 bytes
   - 通过代理下载验证: ✅ 可用

2. **141KB 图片**
   ```
   https://gips1.baidu.com/it/u=1658389554,617110073&fm=3028&app=3028&f=JPEG&fmt=auto?w=1280&h=960
   ```
   - 实际文件大小: ~144,835 bytes
   - 通过代理下载验证: ✅ 可用

3. **115KB 图片**
   ```
   https://gips2.baidu.com/it/u=3944689179,983354166&fm=3028&app=3028&f=JPEG&fmt=auto?w=1024&h=1024
   ```
   - 实际文件大小: ~118,024 bytes
   - 通过代理下载验证: ✅ 可用

---

## 使用方法

### 通过代理下载测试

```bash
# 下载并查看文件大小
curl -x socks5://127.0.0.1:10800 -s "URL" -o /tmp/test.jpg
ls -lh /tmp/test.jpg
```

### 流量统计测试

```bash
# 清零流量统计
curl -s 'http://127.0.0.1:8081/traffic?clear=true' -H "Authorization: test_secret_key_12345" > /dev/null

# 下载文件
curl -x socks5://127.0.0.1:10800 -s "URL" -o /dev/null

# 等待统计更新
sleep 2

# 查看流量统计
curl -s http://127.0.0.1:8081/traffic -H "Authorization: test_secret_key_12345" | jq .
```

---

## 注意事项

### HTTPS 协议开销

通过 HTTPS 代理下载时，流量统计会包含：
- TLS 握手数据
- HTTP 请求头
- HTTP 响应头
- 可能的 TCP 重传

**实测数据**（Phase 0.2 测试结果）：
- 119KB 文件: 实际 121,870 bytes，统计 128,544 bytes，开销 ~5.5%
- 141KB 文件: 实际 144,835 bytes，统计 151,534 bytes，开销 ~4.6%
- 115KB 文件: 实际 118,024 bytes，统计 124,673 bytes，开销 ~5.6%

**结论**: HTTPS 协议开销约为 5-6%，这是正常的网络传输开销。

### 为什么这是正确的行为

流量统计应该包含所有协议开销，因为：
1. 用户实际消耗的流量包含所有网络传输
2. 计费应该基于真实的带宽使用
3. 与 ISP 计费方式一致

---

## 替代测试方案

如果需要测试更大的文件或不同的协议：

### HTTP 测试（无 TLS 开销）
```bash
# 使用 HTTP 而非 HTTPS
http://httpbin.org/bytes/102400
```

### 本地测试服务器
```bash
# 启动本地 HTTP 服务器
python3 -m http.server 8888

# 注意：需要配置 sing-box 允许代理访问 localhost
```

---

**维护说明**: 这些 URL 来自百度图片服务，如果失效请更新为其他可靠的测试资源。
