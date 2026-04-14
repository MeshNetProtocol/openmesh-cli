const { ethers } = require('ethers');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env'), override: true });

const CONTRACT_ADDRESS = process.env.VPN_SUBSCRIPTION_CONTRACT;
const RPC_URL = 'https://sepolia.base.org';

const ABI = ['function getPlan(uint256 planId) external view returns (tuple(string name, uint256 pricePerMonth, uint256 pricePerYear, uint256 trafficLimitDaily, uint256 trafficLimitMonthly, uint8 tier, bool isActive))'];

async function checkPlan() {
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const contract = new ethers.Contract(CONTRACT_ADDRESS, ABI, provider);
  
  console.log('检查 planId 1 是否已存在...\n');
  
  try {
    const plan = await contract.getPlan(1);
    console.log('✅ planId 1 已存在:');
    console.log('  - 名称:', plan.name);
    console.log('  - 月价:', ethers.formatUnits(plan.pricePerMonth, 6), 'USDC');
    console.log('  - 状态:', plan.isActive ? '活跃' : '禁用');
    console.log('\n💡 提示: 可以使用 setPlan 更新现有套餐');
  } catch (error) {
    console.log('❌ planId 1 不存在或查询失败');
    console.log('错误:', error.message);
  }
}

checkPlan();
