#!/usr/bin/env node
/**
 * ⚠️ 测试网专用脚本 - 添加测试套餐
 *
 * 用途: 在测试网上添加一个短周期套餐，用于快速测试自动续费功能
 *
 * 测试套餐参数:
 * - planId: 3
 * - 价格: 0.1 USDC (100000, 6 decimals)
 * - 周期: 30 分钟 (1800 秒)
 * - 配合自动续费预检时间: 10 分钟 (600 秒)
 *
 * ⚠️ 警告: 此套餐仅用于测试网测试，切勿在主网部署！
 *
 * 使用方法:
 * 1. 确保 .env 文件中设置了 OWNER_PRIVATE_KEY
 * 2. 运行: node add_test_plan.js
 * 3. 使用新地址订阅 planId=3 的测试套餐
 * 4. 等待 20 分钟后，自动续费服务会触发续费
 */

// 从父目录加载 .env 文件
require('dotenv').config({ path: '../.env' });
const { ethers } = require('ethers');

// ============================================================================
// 配置
// ============================================================================

const CONTRACT_ADDRESS = process.env.VPN_SUBSCRIPTION_CONTRACT || '0xE9FC83d46590fc7cB603bDA4A25cAb8AF32a02D2';
const RPC_URL = process.env.BASE_SEPOLIA_RPC_URL || 'https://sepolia.base.org';
const PRIVATE_KEY = process.env.OWNER_PRIVATE_KEY;

// ⚠️ 测试套餐参数 (仅用于测试网)
const TEST_PLAN = {
  id: 3,
  price: 100000,        // 0.1 USDC (6 decimals)
  period: 1800,         // 30 分钟 = 1800 秒
  active: true,
  description: '测试套餐 - 30分钟周期'
};

const CONTRACT_ABI = [
  'function setPlan(uint256 id, uint256 price, uint256 period, bool active) external',
  'function plans(uint256) view returns (uint256 price, uint256 period, bool isActive)',
  'function owner() view returns (address)'
];

// ============================================================================
// 主函数
// ============================================================================

async function main() {
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('⚠️  测试网专用: 添加短周期测试套餐');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // 验证私钥
  if (!PRIVATE_KEY) {
    console.error('❌ 错误: 请在 .env 文件中设置 OWNER_PRIVATE_KEY');
    console.error('   提示: 这应该是合约 owner 的私钥');
    process.exit(1);
  }

  // 连接到网络
  console.log('📡 连接到 Base Sepolia 测试网...');
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
  const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, wallet);

  console.log('  合约地址:', CONTRACT_ADDRESS);
  console.log('  Owner 地址:', wallet.address);

  // 验证是否是 owner
  console.log('\n🔍 验证权限...');
  const owner = await contract.owner();
  if (owner.toLowerCase() !== wallet.address.toLowerCase()) {
    console.error('❌ 错误: 当前地址不是合约 owner');
    console.error('  合约 owner:', owner);
    console.error('  当前地址:', wallet.address);
    process.exit(1);
  }
  console.log('✅ 权限验证通过');

  // 显示测试套餐参数
  console.log('\n📦 测试套餐参数:');
  console.log('  planId:', TEST_PLAN.id);
  console.log('  价格:', TEST_PLAN.price, '(0.1 USDC)');
  console.log('  周期:', TEST_PLAN.period, '秒 (30 分钟)');
  console.log('  状态:', TEST_PLAN.active ? '活跃' : '未激活');
  console.log('  说明:', TEST_PLAN.description);

  console.log('\n⚠️  警告: 此套餐仅用于测试自动续费功能');
  console.log('  - 30 分钟订阅周期');
  console.log('  - 配合 10 分钟预检时间');
  console.log('  - 订阅后等待 20 分钟即可触发自动续费');

  // 添加测试套餐
  console.log('\n📤 提交交易...');
  const tx = await contract.setPlan(
    TEST_PLAN.id,
    TEST_PLAN.price,
    TEST_PLAN.period,
    TEST_PLAN.active
  );
  console.log('  交易哈希:', tx.hash);

  console.log('\n⏳ 等待交易确认...');
  const receipt = await tx.wait();
  console.log('✅ 交易已确认!');
  console.log('  Gas used:', receipt.gasUsed.toString());
  console.log('  Block:', receipt.blockNumber);

  // 验证套餐
  console.log('\n🔍 验证套餐...');
  const plan = await contract.plans(TEST_PLAN.id);
  console.log('✅ 测试套餐已成功添加:');
  console.log('  价格:', plan.price.toString(), '(0.1 USDC)');
  console.log('  周期:', plan.period.toString(), '秒 (30 分钟)');
  console.log('  状态:', plan.isActive ? '✅ 活跃' : '❌ 未激活');

  // 使用说明
  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('📝 测试自动续费的步骤:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('1. 修改 .env 文件:');
  console.log('   RENEWAL_PRECHECK_HOURS=0.17  # 10 分钟预检');
  console.log('');
  console.log('2. 重启订阅服务');
  console.log('');
  console.log('3. 使用新地址订阅测试套餐:');
  console.log('   - 在前端选择 planId=3 的套餐');
  console.log('   - 使用一个新的测试钱包地址');
  console.log('   - 确保钱包有足够的 USDC (至少 0.2 USDC)');
  console.log('');
  console.log('4. 添加到自动续费监控:');
  console.log('   curl -X POST http://localhost:3000/api/renewal/add \\');
  console.log('     -H "Content-Type: application/json" \\');
  console.log('     -d \'{"userAddress": "0x..."}\'');
  console.log('');
  console.log('5. 等待 20 分钟后，自动续费服务会触发续费');
  console.log('');
  console.log('6. 观察日志验证自动续费是否成功');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
}

// ============================================================================
// 执行
// ============================================================================

main().catch(error => {
  console.error('\n❌ 执行失败:', error.message);
  if (error.stack) {
    console.error('\n堆栈跟踪:');
    console.error(error.stack);
  }
  process.exit(1);
});
