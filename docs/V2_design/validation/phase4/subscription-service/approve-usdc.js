#!/usr/bin/env node

/**
 * 授权 USDC 给合约
 * 用于自动续费
 */

const path = require('path');
const envPath = path.join(__dirname, '../.env');
require('dotenv').config({ path: envPath, override: true });

const { ethers } = require('ethers');

const CONTRACT_ADDRESS = process.env.VPN_SUBSCRIPTION_CONTRACT;
const USDC_ADDRESS = process.env.USDC_CONTRACT;
const RPC_URL = 'https://sepolia.base.org';

// USDC ABI
const USDC_ABI = [
  'function approve(address spender, uint256 amount) external returns (bool)',
  'function allowance(address owner, address spender) external view returns (uint256)'
];

async function approveUSDC() {
  console.log('🚀 开始授权 USDC...\n');

  // 连接到 Base Sepolia
  const provider = new ethers.JsonRpcProvider(RPC_URL);

  // 使用私钥创建钱包
  const privateKey = process.env.OWNER_PRIVATE_KEY;
  if (!privateKey) {
    console.error('❌ 错误: 未找到 OWNER_PRIVATE_KEY 环境变量');
    process.exit(1);
  }

  const wallet = new ethers.Wallet(privateKey, provider);
  console.log('📝 使用钱包地址:', wallet.address);

  // 连接 USDC 合约
  const usdc = new ethers.Contract(USDC_ADDRESS, USDC_ABI, wallet);
  console.log('📝 USDC 地址:', USDC_ADDRESS);
  console.log('📝 合约地址:', CONTRACT_ADDRESS);

  // 授权 100 USDC (足够多次续费使用)
  const approveAmount = ethers.parseUnits('100', 6);
  console.log('\n📋 授权金额:', ethers.formatUnits(approveAmount, 6), 'USDC');

  console.log('\n⏳ 发送授权交易...');

  try {
    const tx = await usdc.approve(CONTRACT_ADDRESS, approveAmount);
    console.log('📝 交易哈希:', tx.hash);
    console.log('⏳ 等待确认...');

    const receipt = await tx.wait();
    console.log('✅ 交易已确认! Gas 使用:', receipt.gasUsed.toString());

    // 验证授权
    console.log('\n🔍 验证授权...');
    const allowance = await usdc.allowance(wallet.address, CONTRACT_ADDRESS);
    console.log('✅ 当前授权额度:', ethers.formatUnits(allowance, 6), 'USDC');

    console.log('\n✅ 完成! 现在自动续费应该可以正常工作了。');

  } catch (error) {
    console.error('❌ 错误:', error.message);
    if (error.reason) {
      console.error('原因:', error.reason);
    }
    process.exit(1);
  }
}

approveUSDC();
