const { ethers } = require('ethers');
require('dotenv').config({ path: '../.env' });

const VAULT_CONTRACT = "0x9d8fcee6773996de8a8389c343d1711c84c2fb9a";
const USDC_CONTRACT = "0x036CbD53842c5426634e7929541eC2318f3dCF7e";
const RPC_URL = "https://sepolia.base.org";
const IDENTITY_ADDRESS = "0x1234567890123456789012345678901234567890";

async function testSubscriptionFlow() {
  console.log("==========================================");
  console.log("测试智能合约订阅和取消订阅完整流程");
  console.log("==========================================\n");

  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const userWallet = new ethers.Wallet(process.env.OWNER_PRIVATE_KEY, provider);
  const relayerWallet = new ethers.Wallet(process.env.RELAYER_PRIVATE_KEY, provider);
  
  console.log("用户地址:", userWallet.address);
  console.log("Relayer地址:", relayerWallet.address);
  console.log("Identity:", IDENTITY_ADDRESS);
  console.log("");

  const usdcContract = new ethers.Contract(USDC_CONTRACT, [
    "function allowance(address,address) view returns (uint256)",
    "function nonces(address) view returns (uint256)"
  ], provider);
  
  const vaultContract = new ethers.Contract(VAULT_CONTRACT, [
    "function authorizedAllowance(address,address) view returns (uint256)",
    "function authorizeChargeWithPermit(address,address,uint256,uint256,uint256,uint8,bytes32,bytes32)",
    "function cancelAuthorization(address,address,uint256,uint256,uint256,uint8,bytes32,bytes32)"
  ], relayerWallet);

  // ========== 第一步：订阅 ==========
  console.log("========== 第一步：订阅 ==========");
  
  const currentAllowance = await usdcContract.allowance(userWallet.address, VAULT_CONTRACT);
  console.log("1. 当前 USDC allowance:", currentAllowance.toString());

  const vaultAllowance = await vaultContract.authorizedAllowance(userWallet.address, IDENTITY_ADDRESS);
  console.log("2. Vault authorizedAllowance:", vaultAllowance.toString());

  const targetAllowance = currentAllowance + 1000000n;
  console.log("3. 目标 allowance:", targetAllowance.toString(), "(增加 1 USDC)");

  const nonce = await usdcContract.nonces(userWallet.address);
  console.log("4. USDC nonce:", nonce.toString());

  const deadline = Math.floor(Date.now() / 1000) + 86400;
  console.log("5. Deadline:", deadline);

  console.log("6. 生成 permit 签名...");
  const domain = {
    name: 'USDC',
    version: '2',
    chainId: 84532,
    verifyingContract: USDC_CONTRACT
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
    owner: userWallet.address,
    spender: VAULT_CONTRACT,
    value: targetAllowance,
    nonce: nonce,
    deadline: deadline
  };

  const signature = await userWallet.signTypedData(domain, types, value);
  const sig = ethers.Signature.from(signature);
  
  console.log("   签名完成: v=" + sig.v + ", r=" + sig.r.slice(0, 10) + "..., s=" + sig.s.slice(0, 10) + "...");

  console.log("7. 调用 authorizeChargeWithPermit...");
  try {
    const tx = await vaultContract.authorizeChargeWithPermit(
      userWallet.address,
      IDENTITY_ADDRESS,
      currentAllowance,
      targetAllowance,
      deadline,
      sig.v,
      sig.r,
      sig.s
    );
    console.log("   交易已发送:", tx.hash);
    const receipt = await tx.wait();
    console.log("   ✅ 订阅成功! Gas used:", receipt.gasUsed.toString());
  } catch (error) {
    console.log("   ❌ 订阅失败:", error.message);
    return;
  }

  // ========== 第二步：取消订阅 ==========
  console.log("\n========== 第二步：取消订阅 ==========");
  
  const currentAllowance2 = await usdcContract.allowance(userWallet.address, VAULT_CONTRACT);
  console.log("1. 当前 USDC allowance:", currentAllowance2.toString());

  const vaultAllowance2 = await vaultContract.authorizedAllowance(userWallet.address, IDENTITY_ADDRESS);
  console.log("2. Vault authorizedAllowance:", vaultAllowance2.toString());

  const targetAllowance2 = currentAllowance2 - vaultAllowance2;
  console.log("3. 目标 allowance:", targetAllowance2.toString(), "(减少 Vault 授权额度)");

  const nonce2 = await usdcContract.nonces(userWallet.address);
  console.log("4. USDC nonce:", nonce2.toString());

  const deadline2 = Math.floor(Date.now() / 1000) + 86400;
  console.log("5. Deadline:", deadline2);

  console.log("6. 生成 permit 签名 (减少授权)...");
  const value2 = {
    owner: userWallet.address,
    spender: VAULT_CONTRACT,
    value: targetAllowance2,
    nonce: nonce2,
    deadline: deadline2
  };

  const signature2 = await userWallet.signTypedData(domain, types, value2);
  const sig2 = ethers.Signature.from(signature2);
  
  console.log("   签名完成: v=" + sig2.v + ", r=" + sig2.r.slice(0, 10) + "..., s=" + sig2.s.slice(0, 10) + "...");

  console.log("7. 调用 cancelAuthorization...");
  try {
    const tx2 = await vaultContract.cancelAuthorization(
      userWallet.address,
      IDENTITY_ADDRESS,
      currentAllowance2,
      targetAllowance2,
      deadline2,
      sig2.v,
      sig2.r,
      sig2.s
    );
    console.log("   交易已发送:", tx2.hash);
    const receipt2 = await tx2.wait();
    console.log("   ✅ 取消订阅成功! Gas used:", receipt2.gasUsed.toString());
  } catch (error) {
    console.log("   ❌ 取消订阅失败:", error.message);
    return;
  }

  console.log("\n==========================================");
  console.log("测试完成！");
  console.log("==========================================");
}

testSubscriptionFlow().catch(console.error);
