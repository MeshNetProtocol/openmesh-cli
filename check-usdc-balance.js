const { ethers } = require('ethers');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env'), override: true });

const RPC_URL = 'https://sepolia.base.org';
const USDC_ADDRESS = process.env.USDC_CONTRACT;
const CONTRACT_ADDRESS = process.env.VPN_SUBSCRIPTION_CONTRACT;
const USER_ADDRESS = '0x490DC2F60aececAFF22BC670166cbb9d5DdB9241';

const USDC_ABI = [
  'function balanceOf(address) view returns (uint256)',
  'function allowance(address owner, address spender) view returns (uint256)'
];

async function checkBalance() {
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const usdc = new ethers.Contract(USDC_ADDRESS, USDC_ABI, provider);
  
  const balance = await usdc.balanceOf(USER_ADDRESS);
  const allowance = await usdc.allowance(USER_ADDRESS, CONTRACT_ADDRESS);
  
  console.log('USDC 余额:', ethers.formatUnits(balance, 6), 'USDC');
  console.log('授权额度:', ethers.formatUnits(allowance, 6), 'USDC');
  console.log('续费需要:', '0.1 USDC');
  console.log('');
  console.log('余额是否足够:', parseFloat(ethers.formatUnits(balance, 6)) >= 0.1 ? '✅ 是' : '❌ 否');
  console.log('授权是否足够:', parseFloat(ethers.formatUnits(allowance, 6)) >= 0.1 ? '✅ 是' : '❌ 否');
}

checkBalance();
