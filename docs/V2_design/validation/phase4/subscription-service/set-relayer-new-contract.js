const { ethers } = require('ethers');
require('dotenv').config({ path: '../.env' });

const CONTRACT_ADDRESS = '0x85da0a031d4BB90139EFb1C1fB2E1C1D41E8FE00';
const NEW_RELAYER = '0x10AB796695843043CF303Cc8C7a58E9498023768';
const RPC_URL = 'https://sepolia.base.org';

const ABI = [
  'function setRelayer(address _relayer) external',
  'function relayer() external view returns (address)'
];

async function setRelayer() {
  console.log('🔧 设置新合约的 relayer 地址...');
  console.log('合约地址:', CONTRACT_ADDRESS);
  console.log('新 Relayer:', NEW_RELAYER);
  
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const wallet = new ethers.Wallet(process.env.OWNER_PRIVATE_KEY, provider);
  const contract = new ethers.Contract(CONTRACT_ADDRESS, ABI, wallet);
  
  console.log('\n📤 发送交易...');
  const tx = await contract.setRelayer(NEW_RELAYER);
  console.log('交易哈希:', tx.hash);
  
  console.log('⏳ 等待确认...');
  await tx.wait();
  
  console.log('\n✅ Relayer 设置成功!');
  
  const currentRelayer = await contract.relayer();
  console.log('当前 Relayer:', currentRelayer);
}

setRelayer().catch(console.error);
