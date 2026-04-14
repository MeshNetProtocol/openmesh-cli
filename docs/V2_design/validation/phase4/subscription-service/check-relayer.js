const { ethers } = require('ethers');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env'), override: true });

const CONTRACT_ADDRESS = process.env.VPN_SUBSCRIPTION_CONTRACT;
const RPC_URL = 'https://sepolia.base.org';

const ABI = ['function relayer() external view returns (address)'];

async function checkRelayer() {
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const contract = new ethers.Contract(CONTRACT_ADDRESS, ABI, provider);
  
  const relayer = await contract.relayer();
  console.log('合约 Relayer 地址:', relayer);
  console.log('CDP Server Wallet:', '0x10AB796695843043CF303Cc8C7a58E9498023768');
  console.log('是否匹配:', relayer.toLowerCase() === '0x10AB796695843043CF303Cc8C7a58E9498023768'.toLowerCase());
}

checkRelayer();
