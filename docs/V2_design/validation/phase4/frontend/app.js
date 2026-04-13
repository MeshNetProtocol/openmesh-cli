// 配置
const CONFIG = {
  API_BASE: 'http://localhost:3000/api',
  CHAIN_ID: 84532, // Base Sepolia
  USDC_ADDRESS: '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
  CONTRACT_ADDRESS: '0x16D6D1564942798720CB69a6814bc2C53ECe23a1' // V2 合约地址
};

let provider, signer, userAddress;

// 显示状态消息
function showStatus(message, type = 'info') {
  const statusEl = document.getElementById('status');
  statusEl.textContent = message;
  statusEl.className = `status ${type}`;
  statusEl.classList.remove('hidden');
}

// 连接钱包
async function connectWallet() {
  try {
    if (!window.ethereum) {
      showStatus('请安装 MetaMask', 'error');
      return;
    }

    showStatus('连接钱包中...', 'info');

    provider = new ethers.providers.Web3Provider(window.ethereum);
    await provider.send('eth_requestAccounts', []);
    signer = provider.getSigner();
    userAddress = await signer.getAddress();

    // 检查网络
    const network = await provider.getNetwork();
    if (network.chainId !== CONFIG.CHAIN_ID) {
      showStatus('请切换到 Base Sepolia 测试网', 'error');
      return;
    }

    // 显示账户信息
    document.getElementById('address').textContent =
      userAddress.slice(0, 6) + '...' + userAddress.slice(-4);

    document.getElementById('connectSection').classList.add('hidden');
    document.getElementById('accountSection').classList.remove('hidden');

    showStatus('钱包连接成功', 'success');

    // 加载余额和订阅状态
    await Promise.all([loadBalance(), loadSubscription()]);

  } catch (error) {
    console.error('连接失败:', error);
    showStatus('连接失败: ' + error.message, 'error');
  }
}

// 加载 USDC 余额
async function loadBalance() {
  try {
    const usdcAbi = ['function balanceOf(address) view returns (uint256)'];
    const usdc = new ethers.Contract(CONFIG.USDC_ADDRESS, usdcAbi, provider);
    const balance = await usdc.balanceOf(userAddress);
    document.getElementById('balance').textContent =
      ethers.utils.formatUnits(balance, 6) + ' USDC';
  } catch (error) {
    console.error('加载余额失败:', error);
    document.getElementById('balance').textContent = '加载失败';
  }
}

// 加载订阅状态 (V2: 支持多订阅)
async function loadSubscription() {
  try {
    // V2: 查询用户的所有订阅
    const response = await fetch(`${CONFIG.API_BASE}/subscriptions/user/${userAddress}`);
    const data = await response.json();

    const statusEl = document.getElementById('subStatus');

    if (data.subscriptions && data.subscriptions.length > 0) {
      // 显示订阅列表
      let html = `<p style="margin-bottom: 15px;"><strong>您的订阅 (${data.subscriptions.length}):</strong></p>`;

      data.subscriptions.forEach((sub, index) => {
        const expiry = new Date(sub.expiresAt * 1000);
        const isActive = sub.isActive ? '✅ 活跃' : '❌ 已过期';
        const planName = sub.planId === 1 ? '月付' : sub.planId === 2 ? '年付' : '测试套餐';

        html += `
          <div style="border: 1px solid #ddd; padding: 12px; margin-bottom: 10px; border-radius: 4px; background: #f9f9f9;">
            <p><strong>订阅 #${index + 1}</strong></p>
            <p><strong>状态:</strong> ${isActive}</p>
            <p><strong>套餐:</strong> ${planName}</p>
            <p><strong>到期时间:</strong> ${expiry.toLocaleString('zh-CN')}</p>
            <p style="font-size: 12px; color: #666; word-break: break-all;"><strong>VPN 身份:</strong> ${sub.identityAddress}</p>
            ${sub.isActive ? `<button onclick="cancelSubscription('${sub.identityAddress}')" style="margin-top: 8px; padding: 6px 12px; background: #dc3545; color: white; border: none; border-radius: 4px; cursor: pointer;">取消此订阅</button>` : ''}
          </div>
        `;
      });

      statusEl.innerHTML = html;
    } else {
      statusEl.innerHTML = '<p style="color: #666;">暂无订阅</p>';
    }
  } catch (error) {
    console.error('加载订阅失败:', error);
    document.getElementById('subStatus').textContent = '加载失败';
  }
}

// 订阅
async function subscribe() {
  const planId = parseInt(document.getElementById('plan').value);
  const identityAddress = document.getElementById('identity').value.trim();

  if (!ethers.utils.isAddress(identityAddress)) {
    showStatus('请输入有效的身份地址', 'error');
    return;
  }

  const btn = document.getElementById('subBtn');
  btn.disabled = true;
  btn.textContent = '处理中...';

  try {
    showStatus('步骤 1/4: 准备签名数据...', 'info');

    // 1. 获取 EIP-712 签名数据
    const response = await fetch(`${CONFIG.API_BASE}/subscription/prepare`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ userAddress, planId, identityAddress })
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error || '准备订阅失败');
    }

    const { domain, types, value } = await response.json();
    const maxAmount = value.maxAmount;
    const deadline = value.deadline;

    // 2. 用户签名 SubscribeIntent (EIP-712)
    showStatus('步骤 2/4: 签名订阅意图 (MetaMask 第1次)...', 'info');
    const intentSignature = await signer._signTypedData(domain, types, value);

    // 3. 用户签名 USDC Permit (EIP-2612)
    showStatus('步骤 3/4: 授权 USDC 转账 (MetaMask 第2次)...', 'info');

    // 根据网络设置 USDC 的 name (测试网和主网不同)
    const usdcName = CONFIG.CHAIN_ID === 84532 ? 'USDC' : 'USD Coin';  // Base Sepolia: "USDC", Base Mainnet: "USD Coin"

    const usdcDomain = {
      name: usdcName,
      version: '2',
      chainId: CONFIG.CHAIN_ID,
      verifyingContract: CONFIG.USDC_ADDRESS
    };

    const permitTypes = {
      Permit: [
        { name: 'owner', type: 'address' },
        { name: 'spender', type: 'address' },
        { name: 'value', type: 'uint256' },
        { name: 'nonce', type: 'uint256' },
        { name: 'deadline', type: 'uint256' }
      ]
    };

    // 获取 USDC nonce
    const usdcAbi = ['function nonces(address) view returns (uint256)'];
    const usdc = new ethers.Contract(CONFIG.USDC_ADDRESS, usdcAbi, provider);
    const nonce = await usdc.nonces(userAddress);

    const permitValue = {
      owner: userAddress,
      spender: CONFIG.CONTRACT_ADDRESS,
      value: maxAmount,
      nonce: nonce.toNumber(),
      deadline: deadline
    };

    const permitSignature = await signer._signTypedData(usdcDomain, permitTypes, permitValue);

    // 4. 提交订阅
    showStatus('步骤 4/4: 提交订阅交易 (0 ETH gas)...', 'info');
    const subResponse = await fetch(`${CONFIG.API_BASE}/subscription/subscribe`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        userAddress,
        planId,
        identityAddress,
        intentSignature,
        permitSignature,
        maxAmount: maxAmount,
        deadline: deadline,
        nonce: value.nonce
      })
    });

    if (!subResponse.ok) {
      const error = await subResponse.json();
      throw new Error(error.error || '订阅失败');
    }

    const result = await subResponse.json();
    showStatus(`订阅成功! Tx: ${result.txHash.slice(0, 10)}...`, 'success');

    // 刷新状态
    setTimeout(() => {
      loadBalance();
      loadSubscription();
    }, 2000);

  } catch (error) {
    console.error('订阅失败:', error);

    // 友好的错误提示
    let errorMsg = error.message;
    if (errorMsg.includes('already subscribed')) {
      errorMsg = '您已经有活跃的订阅，无需重复订阅';
    } else if (errorMsg.includes('insufficient')) {
      errorMsg = 'USDC 余额不足，请先充值';
    }

    showStatus('订阅失败: ' + errorMsg, 'error');
  } finally {
    btn.disabled = false;
    btn.textContent = '订阅 (0 ETH Gas)';
  }
}

// 取消订阅 (V2: 取消指定身份的订阅)
async function cancelSubscription(identityAddress) {
  if (!confirm(`确定要取消 VPN 身份 ${identityAddress.slice(0, 6)}...${identityAddress.slice(-4)} 的订阅吗?`)) return;

  try {
    showStatus('步骤 1/2: 签名取消意图...', 'info');

    // 1. 获取 cancel nonce
    const nonceResponse = await fetch(`${CONFIG.API_BASE}/cancel-nonce?address=${userAddress}`);
    const { nonce } = await nonceResponse.json();

    // 2. 构造 CancelIntent (V2: 包含 identityAddress)
    const domain = {
      name: 'VPNSubscription',
      version: '2',  // V2
      chainId: CONFIG.CHAIN_ID,
      verifyingContract: CONFIG.CONTRACT_ADDRESS
    };

    const types = {
      CancelIntent: [
        { name: 'user', type: 'address' },
        { name: 'identityAddress', type: 'address' },  // V2 新增
        { name: 'nonce', type: 'uint256' }
      ]
    };

    const value = {
      user: userAddress,
      identityAddress: identityAddress,
      nonce: parseInt(nonce)
    };

    // 3. 用户签名
    const signature = await signer._signTypedData(domain, types, value);

    // 4. 提交取消请求
    showStatus('步骤 2/2: 提交取消交易 (0 ETH gas)...', 'info');
    const response = await fetch(`${CONFIG.API_BASE}/subscription/cancel`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        userAddress,
        identityAddress,
        nonce,
        signature
      })
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error || '取消失败');
    }

    const result = await response.json();
    showStatus(`取消成功! Tx: ${result.txHash.slice(0, 10)}...`, 'success');

    setTimeout(() => {
      loadBalance();
      loadSubscription();
    }, 2000);

  } catch (error) {
    console.error('取消失败:', error);
    showStatus('取消失败: ' + error.message, 'error');
  }
}

// 保留旧的 cancel() 函数用于兼容性（如果 HTML 中有引用）
async function cancel() {
  showStatus('请在订阅列表中点击"取消此订阅"按钮', 'error');
}

// 刷新状态
async function refresh() {
  showStatus('刷新中...', 'info');
  await Promise.all([loadBalance(), loadSubscription()]);
  showStatus('刷新完成', 'success');
  setTimeout(() => {
    document.getElementById('status').classList.add('hidden');
  }, 2000);
}
