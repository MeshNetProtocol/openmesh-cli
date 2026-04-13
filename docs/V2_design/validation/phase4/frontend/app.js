// 配置
const CONFIG = {
  API_BASE: 'http://localhost:3000/api', // 恢复跨域调用 Node 接口
  CHAIN_ID: 84532, // Base Sepolia
  USDC_ADDRESS: '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
  CONTRACT_ADDRESS: '0x99164AAACd45E1F2269ED1a1f91685F757aDF762' // V2.2 测试合约地址
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

    const network = await provider.getNetwork();
    if (network.chainId !== CONFIG.CHAIN_ID) {
      showStatus('请切换到 Base Sepolia 测试网', 'error');
      return;
    }

    document.getElementById('address').textContent = userAddress.slice(0, 6) + '...' + userAddress.slice(-4);
    document.getElementById('connectSection').classList.add('hidden');
    document.getElementById('accountSection').classList.remove('hidden');
    showStatus('钱包连接成功', 'success');

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
    document.getElementById('balance').textContent = ethers.utils.formatUnits(balance, 6) + ' USDC';
  } catch (error) {
    document.getElementById('balance').textContent = '加载失败';
  }
}

// 加载订阅状态 
async function loadSubscription() {
  try {
    const response = await fetch(`${CONFIG.API_BASE}/subscriptions/user/${userAddress}`);
    const data = await response.json();
    const statusEl = document.getElementById('subStatus');

    if (data.subscriptions && data.subscriptions.length > 0) {
      let html = `<p style="margin-bottom: 15px;"><strong>您的订阅 (${data.subscriptions.length}):</strong></p>`;

      data.subscriptions.forEach((sub, index) => {
        const expiry = new Date(sub.expiresAt * 1000);
        const isActive = sub.isActive ? '✅ 活跃' : '❌ 已过期';
        let planName = sub.planId == 1 ? 'Free' : sub.planId == 2 ? 'Basic' : 'Premium';

        html += `
          <div style="border: 1px solid #ddd; padding: 12px; margin-bottom: 15px; border-radius: 4px; background: #f9f9f9;">
            <p><strong>订阅 #${index + 1}</strong></p>
            <p><strong>状态:</strong> ${isActive}</p>
            <p><strong>套餐 ID:</strong> ${sub.planId} (${planName})</p>
            <p><strong>锁定价格:</strong> ${ethers.utils.formatUnits(sub.lockedPrice, 6)} USDC</p>
            <p><strong>到期时间:</strong> ${expiry.toLocaleString('zh-CN')}</p>
            <p style="font-size: 12px; color: #666; word-break: break-all;"><strong>VPN 身份:</strong> ${sub.identityAddress}</p>
            
            <div style="margin-top: 10px; padding-top: 10px; border-top: 1px dashed #ccc;">
              <select id="changePlan_${sub.identityAddress}" style="display:inline-block; width:150px; padding:4px;">
                <option value="2">2 - Basic</option>
                <option value="3">3 - Premium</option>
                <option value="4">4 - 测试套餐 (30分钟)</option>
              </select>
              <label style="font-size: 12px;"><input type="checkbox" id="changeYearly_${sub.identityAddress}">按年</label>
              
              <div style="margin-top: 6px;">
                 <button onclick="doUpgrade('${sub.identityAddress}')" class="btn" style="background:#28a745; padding:6px 12px; font-size:12px;">补差升级</button>
                 <button onclick="doDowngrade('${sub.identityAddress}')" class="btn" style="background:#ffc107; color:#000; padding:6px 12px; font-size:12px;">下月降级</button>
                 <button onclick="doCancelChange('${sub.identityAddress}')" class="btn" style="background:#17a2b8; padding:6px 12px; font-size:12px;">撤销等候降级</button>
              </div>
            </div>

            ${sub.isActive ? `<button onclick="cancelSubscription('${sub.identityAddress}')" style="margin-top: 10px; padding: 6px 12px; background: #dc3545; color: white; border: none; border-radius: 4px; cursor: pointer;">立即挂失/取消自动续费</button>` : ''}
          </div>
        `;
      });

      statusEl.innerHTML = html;
    } else {
      statusEl.innerHTML = '<p style="color: #666;">暂无订阅</p>';
    }
  } catch (error) {
    document.getElementById('subStatus').textContent = '加载失败';
  }
}

// 订阅
async function subscribe() {
  const planId = parseInt(document.getElementById('plan').value);
  const identityAddress = document.getElementById('identity').value.trim();
  const isYearly = document.getElementById('isYearly').checked;

  if (!ethers.utils.isAddress(identityAddress)) {
    showStatus('请输入有效的身份地址', 'error');
    return;
  }

  const btn = document.getElementById('subBtn');
  btn.disabled = true;
  btn.textContent = '处理中...';

  try {
    showStatus('准备签名数据...', 'info');
    const response = await fetch(`${CONFIG.API_BASE}/subscription/prepare`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ userAddress, planId, identityAddress, isYearly })
    });

    if (!response.ok) throw new Error((await response.json()).error);
    const { domain, types, value } = await response.json();
    const maxAmount = value.maxAmount;
    const deadline = value.deadline;

    showStatus('1/2签名订阅意图...', 'info');
    const intentSignature = await signer._signTypedData(domain, types, value);

    let permitSignature = null;
    if (parseInt(maxAmount) > 0) {
      showStatus('2/2签名 USDC Permit 授权...', 'info');
      const usdcName = CONFIG.CHAIN_ID === 84532 ? 'USDC' : 'USD Coin';
      const usdcDomain = { name: usdcName, version: '2', chainId: CONFIG.CHAIN_ID, verifyingContract: CONFIG.USDC_ADDRESS };
      const permitTypes = { Permit: [ { name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }, { name: 'value', type: 'uint256' }, { name: 'nonce', type: 'uint256' }, { name: 'deadline', type: 'uint256' } ] };
      
      const usdcAbi = ['function nonces(address) view returns (uint256)'];
      const usdc = new ethers.Contract(CONFIG.USDC_ADDRESS, usdcAbi, provider);
      const nonce = await usdc.nonces(userAddress);

      permitSignature = await signer._signTypedData(usdcDomain, permitTypes, {
        owner: userAddress, spender: CONFIG.CONTRACT_ADDRESS, value: maxAmount, nonce: nonce.toNumber(), deadline: deadline
      });
    }

    showStatus('提交订阅交易 (0 ETH gas)...', 'info');
    const subResponse = await fetch(`${CONFIG.API_BASE}/subscription/subscribe`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ userAddress, planId, identityAddress, isYearly, intentSignature, permitSignature, maxAmount, deadline, nonce: value.nonce })
    });

    if (!subResponse.ok) throw new Error((await subResponse.json()).error);
    const result = await subResponse.json();
    showStatus(`成功! Tx: ${result.txHash.slice(0, 10)}...`, 'success');

    setTimeout(refresh, 2000);
  } catch (error) {
    showStatus('订阅失败: ' + error.message, 'error');
  } finally {
    btn.disabled = false;
    btn.textContent = '订阅 (0 ETH Gas)';
  }
}

// 升级订阅
async function doUpgrade(identityAddress) {
  const newPlanId = parseInt(document.getElementById(`changePlan_${identityAddress}`).value);
  const isYearly = document.getElementById(`changeYearly_${identityAddress}`).checked;
  
  try {
    const nonceRes = await fetch(`${CONFIG.API_BASE}/intent-nonce?address=${userAddress}`);
    const nonce = (await nonceRes.json()).nonce;
    const deadline = Math.floor(Date.now() / 1000) + 3600;

    // 前端直接写死一个最大的容忍垫付授权差价(实际可以用智能合约预查询)
    const maxAmount = (100 * 1e6).toString(); // 授权最高容忍 100 USDC 差价
    
    const domain = { name: 'VPNSubscription', version: '2', chainId: CONFIG.CHAIN_ID, verifyingContract: CONFIG.CONTRACT_ADDRESS };
    const types = { UpgradeIntent: [ { name: 'user', type: 'address' }, { name: 'identityAddress', type: 'address' }, { name: 'newPlanId', type: 'uint256' }, { name: 'isYearly', type: 'bool' }, { name: 'maxAmount', type: 'uint256' }, { name: 'deadline', type: 'uint256' }, { name: 'nonce', type: 'uint256' } ] };
    const value = { user: userAddress, identityAddress, newPlanId, isYearly, maxAmount, deadline, nonce: parseInt(nonce) };

    showStatus('签名升级意向...', 'info');
    const intentSignature = await signer._signTypedData(domain, types, value);

    showStatus('签名 USDC 差价授权...', 'info');
    const usdcName = CONFIG.CHAIN_ID === 84532 ? 'USDC' : 'USD Coin';
    const usdcDomain = { name: usdcName, version: '2', chainId: CONFIG.CHAIN_ID, verifyingContract: CONFIG.USDC_ADDRESS };
    const permitTypes = { Permit: [ { name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }, { name: 'value', type: 'uint256' }, { name: 'nonce', type: 'uint256' }, { name: 'deadline', type: 'uint256' } ] };
    const usdc = new ethers.Contract(CONFIG.USDC_ADDRESS, ['function nonces(address) view returns (uint256)'], provider);
    const usdcNonce = await usdc.nonces(userAddress);
    const permitSignature = await signer._signTypedData(usdcDomain, permitTypes, {
      owner: userAddress, spender: CONFIG.CONTRACT_ADDRESS, value: maxAmount, nonce: usdcNonce.toNumber(), deadline
    });

    showStatus('验证并发送到链上...', 'info');
    const res = await fetch(`${CONFIG.API_BASE}/subscription/upgrade`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ userAddress, identityAddress, newPlanId, isYearly, maxAmount, deadline, nonce, intentSignature, permitSignature })
    });
    
    if (!res.ok) throw new Error((await res.json()).error);
    showStatus(`升级成功!`, 'success');
    setTimeout(refresh, 2000);
  } catch (error) {
    showStatus('升级失败: ' + error.message, 'error');
  }
}

// 降级订阅
async function doDowngrade(identityAddress) {
  const newPlanId = parseInt(document.getElementById(`changePlan_${identityAddress}`).value);
  try {
    const nonceRes = await fetch(`${CONFIG.API_BASE}/intent-nonce?address=${userAddress}`);
    const nonce = (await nonceRes.json()).nonce;
    const domain = { name: 'VPNSubscription', version: '2', chainId: CONFIG.CHAIN_ID, verifyingContract: CONFIG.CONTRACT_ADDRESS };
    const types = { DowngradeIntent: [ { name: 'user', type: 'address' }, { name: 'identityAddress', type: 'address' }, { name: 'newPlanId', type: 'uint256' }, { name: 'nonce', type: 'uint256' } ] };
    const value = { user: userAddress, identityAddress, newPlanId, nonce: parseInt(nonce) };

    showStatus('签名降级意向...', 'info');
    const intentSignature = await signer._signTypedData(domain, types, value);
    showStatus('提交降级交易...', 'info');
    const res = await fetch(`${CONFIG.API_BASE}/subscription/downgrade`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ userAddress, identityAddress, newPlanId, nonce, intentSignature })
    });
    if (!res.ok) throw new Error((await res.json()).error);
    showStatus(`降级意愿提交成功! 将于下周期生效`, 'success');
  } catch(e) {
    showStatus('降级失败: ' + e.message, 'error');
  }
}

// 取消挂起的变动
async function doCancelChange(identityAddress) {
  try {
    const nonceRes = await fetch(`${CONFIG.API_BASE}/cancel-nonce?address=${userAddress}`);
    const nonce = (await nonceRes.json()).nonce;
    const domain = { name: 'VPNSubscription', version: '2', chainId: CONFIG.CHAIN_ID, verifyingContract: CONFIG.CONTRACT_ADDRESS };
    const types = { CancelChangeIntent: [ { name: 'user', type: 'address' }, { name: 'identityAddress', type: 'address' }, { name: 'nonce', type: 'uint256' } ] };
    const value = { user: userAddress, identityAddress, nonce: parseInt(nonce) };

    showStatus('签名撤销意向...', 'info');
    const intentSignature = await signer._signTypedData(domain, types, value);
    showStatus('提交撤销交易...', 'info');
    const res = await fetch(`${CONFIG.API_BASE}/subscription/cancel-change`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ userAddress, identityAddress, nonce, intentSignature })
    });
    if (!res.ok) throw new Error((await res.json()).error);
    showStatus(`撤销挂起变动成功!`, 'success');
  } catch(e) {
    showStatus('撤销失败: ' + e.message, 'error');
  }
}

// 取消订阅
async function cancelSubscription(identityAddress) {
  if (!confirm(`确定挂失该 VPN 身份吗?`)) return;
  try {
    const nonceResponse = await fetch(`${CONFIG.API_BASE}/cancel-nonce?address=${userAddress}`);
    const { nonce } = await nonceResponse.json();
    const domain = { name: 'VPNSubscription', version: '2', chainId: CONFIG.CHAIN_ID, verifyingContract: CONFIG.CONTRACT_ADDRESS };
    const types = { CancelIntent: [ { name: 'user', type: 'address' }, { name: 'identityAddress', type: 'address' }, { name: 'nonce', type: 'uint256' } ] };
    const value = { user: userAddress, identityAddress, nonce: parseInt(nonce) };

    const signature = await signer._signTypedData(domain, types, value);
    showStatus('提交取消请求...', 'info');
    const response = await fetch(`${CONFIG.API_BASE}/subscription/cancel`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ userAddress, identityAddress, nonce, signature })
    });
    if (!response.ok) throw new Error((await response.json()).error);
    showStatus(`取消/停止续费成功!`, 'success');
    setTimeout(refresh, 2000);
  } catch (error) { showStatus('取消失败: ' + error.message, 'error'); }
}

async function cancel() { showStatus('请在订阅列表中点击"取消此订阅/挂失"按钮', 'error'); }
async function refresh() { showStatus('刷新中...', 'info'); await Promise.all([loadBalance(), loadSubscription()]); showStatus('刷新完成', 'success'); setTimeout(() => { document.getElementById('status').classList.add('hidden'); }, 2000); }
