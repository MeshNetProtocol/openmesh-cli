#!/usr/bin/env node

/**
 * 添加 30 分钟测试套餐
 * 用于测试自动续费功能
 */

const path = require('path');
const envPath = path.join(__dirname, '../.env');
require('dotenv').config({ path: envPath, override: true });

const { ethers } = require('ethers');

const CONTRACT_ADDRESS = process.env.VPN_SUBSCRIPTION_CONTRACT;
const RPC_URL = 'https://sepolia.base.org';

// 合约 ABI (只需要 setPlan 函数)
const CONTRACT_ABI = [
  'function setPlan(uint256 id, string memory name, uint256 pricePerMonth, uint256 pricePerYear, uint256 period, uint256 trafficLimitDaily, uint256 trafficLimitMonthly, uint8 tier, bool active) external',
  'function getPlan(uint256 planId) external view returns (tuple(string name, uint256 pricePerMonth, uint256 pricePerYear, uint256 trafficLimitDaily, uint256 trafficLimitMonthly, uint8 tier, bool isActive))'
];

async function addTestPlan() {
  console.log('🚀 开始添加 30 分钟测试套餐...\n');

  // 连接到 Base Sepolia (ethers v6 语法)
  const provider = new ethers.JsonRpcProvider(RPC_URL);

  // 使用私钥创建钱包 (需要是合约 owner)
  const privateKey = process.env.OWNER_PRIVATE_KEY;
  if (!privateKey) {
    console.error('❌ 错误: 未找到 OWNER_PRIVATE_KEY 环境变量');
    process.exit(1);
  }

  const wallet = new ethers.Wallet(privateKey, provider);
  console.log('📝 使用钱包地址:', wallet.address);

  // 连接合约
  const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, wallet);
  console.log('📝 合约地址:', CONTRACT_ADDRESS);

  // 30 分钟测试套餐配置
  const testPlan = {
    planId: 1,  // planId 1 (Free 套餐位置)
    name: '自动续费测试桩',
    pricePerMonth: ethers.parseUnits('0.1', 6),  // 0.1 USDC (6 decimals)
    pricePerYear: ethers.parseUnits('0.1', 6),   // 年付也是 0.1 USDC
    period: 30 * 60,  // 30 分钟 = 1800 秒
    trafficLimitDaily: ethers.parseUnits('100', 6),  // 100 MB
    trafficLimitMonthly: 0,  // 无月限制
    tier: 0,
    active: true  // 激活套餐
  };

  console.log('\n📋 套餐配置:');
  console.log('  - planId:', testPlan.planId);
  console.log('  - 名称:', testPlan.name);
  console.log('  - 月价:', ethers.formatUnits(testPlan.pricePerMonth, 6), 'USDC');
  console.log('  - 年价:', ethers.formatUnits(testPlan.pricePerYear, 6), 'USDC');
  console.log('  - 订阅周期:', testPlan.period, '秒 (30 分钟)');
  console.log('  - 日流量限制:', ethers.formatUnits(testPlan.trafficLimitDaily, 6), 'MB');
  console.log('  - 月流量限制:', testPlan.trafficLimitMonthly === 0 ? '无限' : testPlan.trafficLimitMonthly);
  console.log('  - 层级:', testPlan.tier);
  console.log('  - 状态:', testPlan.active ? '活跃' : '禁用');

  console.log('\n⏳ 发送交易...');

  try {
    const tx = await contract.setPlan(
      testPlan.planId,
      testPlan.name,
      testPlan.pricePerMonth,
      testPlan.pricePerYear,
      testPlan.period,
      testPlan.trafficLimitDaily,
      testPlan.trafficLimitMonthly,
      testPlan.tier,
      testPlan.active
    );

    console.log('📝 交易哈希:', tx.hash);
    console.log('⏳ 等待确认...');

    const receipt = await tx.wait();
    console.log('✅ 交易已确认! Gas 使用:', receipt.gasUsed.toString());

    // 验证套餐是否添加成功
    console.log('\n🔍 验证套餐...');
    const plan = await contract.getPlan(testPlan.planId);
    console.log('✅ 套餐已成功添加:');
    console.log('  - 名称:', plan.name);
    console.log('  - 月价:', ethers.formatUnits(plan.pricePerMonth, 6), 'USDC');
    console.log('  - 状态:', plan.isActive ? '活跃' : '禁用');

    console.log('\n✅ 完成! 现在可以在前端看到这个测试套餐了。');
    console.log('💡 提示: 这个套餐的订阅周期是 30 分钟,适合测试自动续费功能。');

  } catch (error) {
    console.error('❌ 错误:', error.message);
    if (error.reason) {
      console.error('原因:', error.reason);
    }
    process.exit(1);
  }
}

addTestPlan();
