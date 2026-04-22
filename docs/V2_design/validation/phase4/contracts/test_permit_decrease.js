const { ethers } = require('ethers');

async function testPermitDecrease() {
  const provider = new ethers.JsonRpcProvider('https://sepolia.base.org');
  const wallet = new ethers.Wallet('0x029383f905828598c37853acaa2124209125dae1b9a6e98e04339bb45c744c2e', provider);
  
  const USDC_ADDRESS = '0x036CbD53842c5426634e7929541eC2318f3dCF7e';
  const VAULT_ADDRESS = '0x9d8fcee6773996de8a8389c343d1711c84c2fb9a';
  
  const usdc = new ethers.Contract(USDC_ADDRESS, [
    'function nonces(address) view returns (uint256)',
    'function permit(address,address,uint256,uint256,uint8,bytes32,bytes32)',
    'function allowance(address,address) view returns (uint256)'
  ], wallet);
  
  const currentAllowance = await usdc.allowance(wallet.address, VAULT_ADDRESS);
  const nonce = await usdc.nonces(wallet.address);
  const deadline = Math.floor(Date.now() / 1000) + 86400;
  
  console.log('当前 allowance:', currentAllowance.toString());
  console.log('当前 nonce:', nonce.toString());
  console.log('尝试将 allowance 从', currentAllowance.toString(), '减少到 0');
  
  // 签名 permit，将 allowance 从当前值减少到 0
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
    value: 0, // 目标 allowance = 0
    nonce: nonce,
    deadline: deadline
  };
  
  const signature = await wallet.signTypedData(domain, types, value);
  const sig = ethers.Signature.from(signature);
  
  console.log('✅ 签名成功');
  console.log('执行 permit...');
  
  try {
    // 模拟执行，看看是否会 revert
    await usdc.permit.staticCall(
      wallet.address,
      VAULT_ADDRESS,
      0,
      deadline,
      sig.v,
      sig.r,
      sig.s
    );
    console.log('✅ Permit staticCall 成功（不会 revert）');
    
    // 实际执行
    const tx = await usdc.permit(
      wallet.address,
      VAULT_ADDRESS,
      0,
      deadline,
      sig.v,
      sig.r,
      sig.s
    );
    console.log('✅ Permit 交易已发送:', tx.hash);
    await tx.wait();
    console.log('✅ 交易已确认');
    
    const newAllowance = await usdc.allowance(wallet.address, VAULT_ADDRESS);
    console.log('新的 allowance:', newAllowance.toString());
    
    if (newAllowance.toString() === '0') {
      console.log('✅ Allowance 成功减少到 0');
    } else {
      console.log('⚠️  Allowance 没有改变！');
    }
  } catch (error) {
    console.log('❌ Permit 执行失败（会 revert）');
    console.log('Error:', error.shortMessage || error.message);
    if (error.data) {
      console.log('Error data:', error.data);
    }
  }
}

testPermitDecrease().catch(console.error);
