const { ethers } = require('ethers');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env'), override: true });

const CONTRACT_ADDRESS = process.env.VPN_SUBSCRIPTION_CONTRACT;
const RPC_URL = 'https://sepolia.base.org';

const ABI = ['function owner() external view returns (address)'];

async function checkOwner() {
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const contract = new ethers.Contract(CONTRACT_ADDRESS, ABI, provider);
  
  const owner = await contract.owner();
  console.log('合约 Owner 地址:', owner);
  console.log('当前钱包地址:', '0x490DC2F60aececAFF22BC670166cbb9d5DdB9241');
  console.log('是否匹配:', owner.toLowerCase() === '0x490DC2F60aececAFF22BC670166cbb9d5DdB9241'.toLowerCase());
}

checkOwner();
