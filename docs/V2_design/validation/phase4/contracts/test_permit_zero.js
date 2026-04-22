const { ethers } = require('ethers');

async function testPermitZero() {
  const provider = new ethers.JsonRpcProvider('https://sepolia.base.org');
  const wallet = new ethers.Wallet('0x029383f905828598c37853acaa2124209125dae1b9a6e98e04339bb45c744c2e', provider);
  
  const USDC_ADDRESS = '0x036CbD53842c5426634e7929541eC2318f3dCF7e';
  const VAULT_ADDRESS = '0x9d8fcee6773996de8a8389c343d1711c84c2fb9a';
  
  const usdc = new ethers.Contract(USDC_ADDRESS, [
    'function nonces(address) view returns (uint256)',
    'function permit(address,address,uint256,uint256,uint8,bytes32,bytes32)'
  ], wallet);
  
  const nonce = await usdc.nonces(wallet.address);
  const deadline = Math.floor(Date.now() / 1000) + 86400;
  
  // 尝试签名 value=0 的 permit
  const domain = {
    name: 'USDC',
    version: '2',
    chainId: 84532,
    verifyingContract: USDC_ADDRESS
  };
  
  const types = {
    Permit: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
      { name: 'value', type: 'uint256' },
      { name: 'nonce', type: 'uint256' },
      { name: 'deadline', type: 'uint256' }
    ]
  };
  
  const value = {
    owner: wallet.address,
    spender: VAULT_ADDRESS,
    value: 0, // 测试 value=0
    nonce: nonce,
    deadline: deadline
  };
  
  try {
    const signature = await wallet.signTypedData(domain, types, value);
    console.log('✅ 签名成功! value=0 是允许的');
    console.log('Signature:', signature);
  } catch (error) {
    console.log('❌ 签名失败! value=0 不允许');
    console.log('Error:', error.message);
  }
}

testPermitZero().catch(console.error);
