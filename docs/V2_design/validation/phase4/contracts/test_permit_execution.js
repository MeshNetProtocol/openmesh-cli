const { ethers } = require('ethers');

async function testPermitExecution() {
  const provider = new ethers.JsonRpcProvider('https://sepolia.base.org');
  const wallet = new ethers.Wallet('0x029383f905828598c37853acaa2124209125dae1b9a6e98e04339bb45c744c2e', provider);
  
  const USDC_ADDRESS = '0x036CbD53842c5426634e7929541eC2318f3dCF7e';
  const VAULT_ADDRESS = '0x9d8fcee6773996de8a8389c343d1711c84c2fb9a';
  
  const usdc = new ethers.Contract(USDC_ADDRESS, [
    'function nonces(address) view returns (uint256)',
    'function permit(address,address,uint256,uint256,uint8,bytes32,bytes32)',
    'function allowance(address,address) view returns (uint256)'
  ], wallet);
  
  const nonce = await usdc.nonces(wallet.address);
  const deadline = Math.floor(Date.now() / 1000) + 86400;
  
  console.log('当前 nonce:', nonce.toString());
  console.log('当前 allowance:', (await usdc.allowance(wallet.address, VAULT_ADDRESS)).toString());
  
  // 尝试签名并执行 value=0 的 permit
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
    value: 0,
    nonce: nonce,
    deadline: deadline
  };
  
  const signature = await wallet.signTypedData(domain, types, value);
  const sig = ethers.Signature.from(signature);
  
  console.log('✅ 签名成功');
  console.log('尝试执行 permit...');
  
  try {
    const tx = await usdc.permit(
      wallet.address,
      VAULT_ADDRESS,
      0,
      deadline,
      sig.v,
      sig.r,
      sig.s
    );
    console.log('✅ Permit 执行成功! TX:', tx.hash);
    await tx.wait();
    console.log('✅ 交易已确认');
    console.log('新的 allowance:', (await usdc.allowance(wallet.address, VAULT_ADDRESS)).toString());
  } catch (error) {
    console.log('❌ Permit 执行失败!');
    console.log('Error:', error.message);
    if (error.data) {
      console.log('Error data:', error.data);
    }
  }
}

testPermitExecution().catch(console.error);
