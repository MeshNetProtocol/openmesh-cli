require('dotenv').config({ path: '../.env' });
const { ethers } = require('ethers');

const CONTRACT_ADDRESS = '0xE9FC83d46590fc7cB603bDA4A25cAb8AF32a02D2';
const RPC_URL = 'https://sepolia.base.org';

const ABI = ['function plans(uint256) view returns (uint256 price, uint256 period, bool isActive)'];

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const contract = new ethers.Contract(CONTRACT_ADDRESS, ABI, provider);

  console.log('查询测试套餐 (planId=3)...\n');
  const plan = await contract.plans(3);

  console.log('价格:', plan.price.toString(), 'USDC (6 decimals)');
  console.log('周期:', plan.period.toString(), '秒');
  console.log('状态:', plan.isActive ? '✅ 活跃' : '❌ 未激活');
}

main().catch(console.error);
