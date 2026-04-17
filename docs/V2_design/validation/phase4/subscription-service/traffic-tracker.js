/**
 * 流量追踪服务
 *
 * 功能:
 * 1. 从 VPN 服务器接收流量使用数据
 * 2. 检查流量限制并暂停超限服务
 * 3. 定期重置日/月流量
 * 4. 上报流量到合约
 */

const { ethers } = require('ethers');
const { sendTransactionViaCDP } = require('./cdp-transaction');
const { loadDB, addTrafficUsage, clearTrafficUsage, removeIdentity, trackIdentity } = require('./mock-db');

// 合约 ABI
const CONTRACT_ABI = [
  'function reportTrafficUsage(address identityAddress, uint256 bytesUsed) external',
  'function checkTrafficLimit(address identityAddress) external view returns (bool isWithinLimit, uint256 dailyRemaining, uint256 monthlyRemaining)',
  'function suspendForTrafficLimit(address identityAddress) external',
  'function resetDailyTraffic(address identityAddress) external',
  'function resetMonthlyTraffic(address identityAddress) external',
  'function resumeAfterReset(address identityAddress) external',
  'function getSubscription(address identityAddress) external view returns (address identityAddress, address payerAddress, uint96 lockedPrice, uint256 planId, uint256 lockedPeriod, uint256 startTime, uint256 expiresAt, bool autoRenewEnabled, uint256 nextPlanId, uint256 trafficUsedDaily, uint256 trafficUsedMonthly, uint256 lastResetDaily, uint256 lastResetMonthly, bool isSuspended)',
];

class TrafficTracker {
  constructor({ cdpClient, serverWalletAccount, contractAddress, paymasterEndpoint, provider }) {
    this.cdpClient = cdpClient;
    this.serverWalletAccount = serverWalletAccount;
    this.contractAddress = contractAddress;
    this.paymasterEndpoint = paymasterEndpoint;
    this.provider = provider;

    // 配置
    this.reportIntervalSeconds = parseInt(process.env.TRAFFIC_REPORT_INTERVAL_SECONDS || '300'); // 5分钟
    this.resetCheckIntervalSeconds = parseInt(process.env.TRAFFIC_RESET_CHECK_INTERVAL_SECONDS || '3600'); // 1小时
    this.batchSize = parseInt(process.env.TRAFFIC_BATCH_SIZE || '10');

    // 使用 JSON 文件做本地持久化 (替代之前的内存 Map)
    // db.trafficBuffer: identityAddress -> bytesUsed
    // db.lastResetCheck: identityAddress -> { daily: timestamp, monthly: timestamp }


    console.log('📊 流量追踪服务配置:');
    console.log(`  上报间隔: ${this.reportIntervalSeconds} 秒`);
    console.log(`  重置检查间隔: ${this.resetCheckIntervalSeconds} 秒`);
    console.log(`  批量大小: ${this.batchSize}`);
  }

  /**
   * 启动流量追踪服务
   */
  start() {
    console.log('🚀 启动流量追踪服务...');

    // 定期上报流量
    this.reportIntervalId = setInterval(() => {
      this.reportTraffic();
    }, this.reportIntervalSeconds * 1000);

    // 定期检查流量重置
    this.resetIntervalId = setInterval(() => {
      this.checkTrafficReset();
    }, this.resetCheckIntervalSeconds * 1000);

    console.log('✅ 流量追踪服务已启动');
  }

  /**
   * 停止流量追踪服务
   */
  stop() {
    if (this.reportIntervalId) {
      clearInterval(this.reportIntervalId);
    }
    if (this.resetIntervalId) {
      clearInterval(this.resetIntervalId);
    }
    console.log('⏹️  流量追踪服务已停止');
  }

  /**
   * 记录流量使用 (从 VPN 服务器调用)
   */
  recordTraffic(identityAddress, bytesUsed) {
    // 写入 JSON 数据库
    const current = addTrafficUsage(identityAddress, bytesUsed);
    trackIdentity(identityAddress); // 加入常规检测列表

    console.log(`📈 记录流量: ${identityAddress} +${this.formatBytes(bytesUsed)} (待上报合计: ${this.formatBytes(current)})`);
  }

  /**
   * 上报流量到合约
   */
  async reportTraffic() {
    const db = loadDB();
    const entries = Object.entries(db.trafficBuffer);

    if (entries.length === 0) {
      console.log('📊 没有待上报的流量数据');
      return;
    }

    console.log(`\n📤 开始上报流量 (${entries.length} 个身份)...`);

    for (let i = 0; i < entries.length; i += this.batchSize) {
      const batch = entries.slice(i, i + this.batchSize);

      for (const [identityAddress, bytesUsed] of batch) {
        try {
          await this.reportSingleTraffic(identityAddress, bytesUsed);

          // 上报成功后清除缓存
          clearTrafficUsage(identityAddress);

          // 检查是否超限
          await this.checkAndSuspendIfNeeded(identityAddress);
        } catch (error) {
          console.error(`❌ 上报流量失败 (${identityAddress}):`, error.message);

          if (this.shouldDropIdentity(error)) {
            console.warn(`⚠️  丢弃无效身份，停止重试: ${identityAddress}`);
            removeIdentity(identityAddress);
            continue;
          }

          // 保留在缓存中,下次重试
        }
      }
    }

    console.log('✅ 流量上报完成');
  }

  /**
   * 上报单个身份的流量
   */
  async reportSingleTraffic(identityAddress, bytesUsed) {
    console.log(`  上报: ${identityAddress} ${this.formatBytes(bytesUsed)}`);

    const contract = new ethers.Contract(this.contractAddress, CONTRACT_ABI, this.provider);
    const subscription = await contract.getSubscription(identityAddress);
    const startTime = Number(subscription.startTime ?? subscription[5] ?? 0);
    const expiresAt = Number(subscription.expiresAt ?? subscription[6] ?? 0);
    const isSuspended = Boolean(subscription.isSuspended ?? subscription[13] ?? subscription[15] ?? false);
    const now = Math.floor(Date.now() / 1000);

    if (startTime === 0 || expiresAt <= now || isSuspended) {
      const reason = startTime === 0
        ? 'subscription not found'
        : expiresAt <= now
          ? 'subscription expired'
          : 'subscription suspended';
      const error = new Error(`skip traffic report: ${reason}`);
      error.code = 'DROP_IDENTITY';
      throw error;
    }

    const data = contract.interface.encodeFunctionData('reportTrafficUsage', [
      identityAddress,
      bytesUsed
    ]);

    await sendTransactionViaCDP({
      cdpClient: this.cdpClient,
      account: this.serverWalletAccount,
      contractAddress: this.contractAddress,
      calldata: data,
      network: 'base-sepolia',
    });

    console.log(`  ✅ 上报成功: ${identityAddress}`);
  }

  /**
   * 检查流量限制并暂停服务
   */
  async checkAndSuspendIfNeeded(identityAddress) {
    try {
      const contract = new ethers.Contract(this.contractAddress, CONTRACT_ABI, this.provider);
      const result = await contract.checkTrafficLimit(identityAddress);

      // 合约返回: (bool isWithinLimit, uint256 dailyRemaining, uint256 monthlyRemaining)
      const { isWithinLimit, dailyRemaining, monthlyRemaining } = result;

      if (!isWithinLimit) {
        console.log(`⚠️  流量超限: ${identityAddress}`);
        console.log(`  日剩余流量: ${this.formatBytes(dailyRemaining)}`);
        console.log(`  月剩余流量: ${this.formatBytes(monthlyRemaining)}`);

        // 暂停服务
        await this.suspendService(identityAddress);
      }
    } catch (error) {
      console.error(`❌ 检查流量限制失败 (${identityAddress}):`, error.message);
    }
  }

  /**
   * 暂停服务
   */
  async suspendService(identityAddress) {
    console.log(`🚫 暂停服务: ${identityAddress}`);

    const contract = new ethers.Contract(this.contractAddress, CONTRACT_ABI, this.provider);
    const data = contract.interface.encodeFunctionData('suspendForTrafficLimit', [identityAddress]);

    await sendTransactionViaCDP({
      cdpClient: this.cdpClient,
      account: this.serverWalletAccount,
      contractAddress: this.contractAddress,
      calldata: data,
      network: 'base-sepolia',
    });

    console.log(`  ✅ 服务已暂停: ${identityAddress}`);
  }

  /**
   * 检查并执行流量重置
   */
  async checkTrafficReset() {
    console.log('\n🔄 检查流量重置...');

    // 从 JSON 数据库查询所有被跟踪的订阅身份
    const db = loadDB();
    const identities = Object.keys(db.lastResetCheck);

    if (identities.length === 0) {
      console.log('  没有需要检查的订阅');
      return;
    }

    for (const identityAddress of identities) {
      try {
        await this.checkAndResetTraffic(identityAddress);
      } catch (error) {
        console.error(`❌ 检查流量重置失败 (${identityAddress}):`, error.message);
      }
    }

    console.log('✅ 流量重置检查完成');
  }

  /**
   * 检查并重置单个身份的流量
   */
  async checkAndResetTraffic(identityAddress) {
    const contract = new ethers.Contract(this.contractAddress, CONTRACT_ABI, this.provider);
    const subscription = await contract.getSubscription(identityAddress);

    if (Number(subscription.startTime) === 0) {
      return;
    }

    const now = Math.floor(Date.now() / 1000);
    const lastResetDaily = Number(subscription.lastResetDaily);
    const lastResetMonthly = Number(subscription.lastResetMonthly);

    // 检查是否需要重置日流量 (每天 UTC 00:00)
    const daysSinceReset = Math.floor((now - lastResetDaily) / 86400);
    if (daysSinceReset >= 1) {
      console.log(`  重置日流量: ${identityAddress}`);
      await this.resetDailyTraffic(identityAddress);
    }

    // 检查是否需要重置月流量 (每月1号 UTC 00:00)
    const currentMonth = new Date(now * 1000).getUTCMonth();
    const lastResetMonth = new Date(lastResetMonthly * 1000).getUTCMonth();
    if (currentMonth !== lastResetMonth) {
      console.log(`  重置月流量: ${identityAddress}`);
      await this.resetMonthlyTraffic(identityAddress);
    }
  }

  /**
   * 重置日流量
   */
  async resetDailyTraffic(identityAddress) {
    const contract = new ethers.Contract(this.contractAddress, CONTRACT_ABI, this.provider);
    const data = contract.interface.encodeFunctionData('resetDailyTraffic', [identityAddress]);

    await sendTransactionViaCDP({
      cdpClient: this.cdpClient,
      account: this.serverWalletAccount,
      contractAddress: this.contractAddress,
      calldata: data,
      network: 'base-sepolia',
    });

    // 恢复服务
    await this.resumeService(identityAddress);
  }

  /**
   * 重置月流量
   */
  async resetMonthlyTraffic(identityAddress) {
    const contract = new ethers.Contract(this.contractAddress, CONTRACT_ABI, this.provider);
    const data = contract.interface.encodeFunctionData('resetMonthlyTraffic', [identityAddress]);

    await sendTransactionViaCDP({
      cdpClient: this.cdpClient,
      account: this.serverWalletAccount,
      contractAddress: this.contractAddress,
      calldata: data,
      network: 'base-sepolia',
    });

    // 恢复服务
    await this.resumeService(identityAddress);
  }

  /**
   * 恢复服务
   */
  async resumeService(identityAddress) {
    const contract = new ethers.Contract(this.contractAddress, CONTRACT_ABI, this.provider);
    const data = contract.interface.encodeFunctionData('resumeAfterReset', [identityAddress]);

    await sendTransactionViaCDP({
      cdpClient: this.cdpClient,
      account: this.serverWalletAccount,
      contractAddress: this.contractAddress,
      calldata: data,
      network: 'base-sepolia',
    });

    console.log(`  ✅ 服务已恢复: ${identityAddress}`);
  }

  /**
   * 查询流量使用情况
   */
  async getTrafficUsage(identityAddress) {
    const contract = new ethers.Contract(this.contractAddress, CONTRACT_ABI, this.provider);
    const result = await contract.checkTrafficLimit(identityAddress);

    // 合约返回: (bool isWithinLimit, uint256 dailyRemaining, uint256 monthlyRemaining)
    return {
      withinLimit: result.isWithinLimit,
      daily: {
        remaining: this.formatBytes(result.dailyRemaining),
        remainingBytes: result.dailyRemaining.toString(),
      },
      monthly: {
        remaining: this.formatBytes(result.monthlyRemaining),
        remainingBytes: result.monthlyRemaining.toString(),
      },
    };
  }

  /**
   * 格式化字节数
   */
  formatBytes(bytes) {
    const b = BigInt(bytes);
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    let value = Number(b);
    let unitIndex = 0;

    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }

    return `${value.toFixed(2)} ${units[unitIndex]}`;
  }

  shouldDropIdentity(error) {
    if (!error) return false;
    if (error.code === 'DROP_IDENTITY') return true;

    const message = String(error.message || '').toLowerCase();
    return message.includes('vpn: not active');
  }
}

module.exports = { TrafficTracker };
