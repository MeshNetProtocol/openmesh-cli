// 配置
const CONFIG = {
  API_BASE: 'http://localhost:3000/api',
  CHAIN_ID: 84532, // Base Sepolia
  USDC_ADDRESS: '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
  CONTRACT_ADDRESS: '0xe96b8843e8F3dCce5156c1AA34233cfe49a5ff83' // V2.2 合约地址 (移除 isActive 字段)
};

let provider, signer, userAddress;
let availablePlans = []; // 存储从后端获取的套餐列表

// 显示状态消息
function showStatus(message, type = 'info') {
  const statusEl = document.getElementById('status');
  statusEl.textContent = message;
  statusEl.className = `status ${type}`;
  statusEl.classList.remove('hidden');
}

// 加载套餐列表
async function loadPlans() {
  try {
    const response = await fetch(`${CONFIG.API_BASE}/plans`);
    const data = await response.json();
    availablePlans = data.plans || [];

    // 更新套餐选择下拉框
    const planSelect = document.getElementById('plan');
    planSelect.innerHTML = '';

    availablePlans.forEach(plan => {
      const option = document.createElement('option');
      option.value = plan.planId;

      const monthlyPrice = (plan.pricePerMonth / 1e6).toFixed(2);
      const yearlyPrice = (plan.pricePerYear / 1e6).toFixed(2);
      const dailyLimit = plan.trafficLimitDaily === '0' ? '无限' : `${(plan.trafficLimitDaily / 1e9).toFixed(0)} GB`;
      const monthlyLimit = plan.trafficLimitMonthly === '0' ? '无限' : `${(plan.trafficLimitMonthly / 1e9).toFixed(0)} GB`;

      option.textContent = `${plan.name} - $${monthlyPrice}/月 或 $${yearlyPrice}/年 (日限: ${dailyLimit}, 月限: ${monthlyLimit})`;
      planSelect.appendChild(option);
    });

    console.log('已加载套餐:', availablePlans);
  } catch (error) {
    console.error('加载套餐失败:', error);
    showStatus('加载套餐失败: ' + error.message, 'error');
  }
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

    await Promise.all([loadPlans(), loadBalance(), loadSubscription()]);
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
    const response = await fetch(`${CONFIG.API_BASE}/subscription/${userAddress}`);
    const data = await response.json();
    const statusEl = document.getElementById('subStatus');

    if (data.subscriptions && data.subscriptions.length > 0) {
      // ✅ 修复：过滤掉已过期的订阅
      const now = Math.floor(Date.now() / 1000);
      const activeSubscriptions = data.subscriptions.filter(sub => {
        // 真实的活跃状态 = 未过期 且 isActive
        return sub.expiresAt > now && sub.isActive;
      });

      if (activeSubscriptions.length === 0) {
        statusEl.innerHTML = '<p>您当前没有活跃的订阅</p>';
        return;
      }

      let html = `<p style="margin-bottom: 15px;"><strong>您的订阅 (${activeSubscriptions.length}):</strong></p>`;

      for (const sub of activeSubscriptions) {
        const expiry = new Date(sub.expiresAt * 1000);
        const plan = availablePlans.find(p => p.planId === sub.planId);
        const planName = plan ? plan.name : `Plan ${sub.planId}`;

        // ✅ 修复：根据 autoRenewEnabled 显示不同的状态提示
        let statusText = '';
        if (sub.autoRenewEnabled) {
          statusText = '✅ 活跃 - 将自动续费';
        } else {
          statusText = '✅ 活跃 - 到期后失效';
        }

        // 加载流量使用情况
        let trafficHtml = '';
        try {
          const trafficResponse = await fetch(`${CONFIG.API_BASE}/traffic/${sub.identityAddress}`);
          const trafficData = await trafficResponse.json();

          if (trafficData.success) {
            const dailyUsed = (trafficData.dailyUsed / 1e6).toFixed(2);
            const dailyLimit = trafficData.dailyLimit === '0' ? '无限' : (trafficData.dailyLimit / 1e9).toFixed(2);
            const monthlyUsed = (trafficData.monthlyUsed / 1e6).toFixed(2);
            const monthlyLimit = trafficData.monthlyLimit === '0' ? '无限' : (trafficData.monthlyLimit / 1e9).toFixed(2);

            const dailyPercent = trafficData.dailyLimit === '0' ? 0 : (trafficData.dailyUsed / trafficData.dailyLimit * 100).toFixed(1);
            const monthlyPercent = trafficData.monthlyLimit === '0' ? 0 : (trafficData.monthlyUsed / trafficData.monthlyLimit * 100).toFixed(1);

            trafficHtml = `
              <div style="margin-top: 10px; padding: 10px; background: #f0f8ff; border-radius: 4px;">
                <p style="font-weight: bold; margin-bottom: 8px;">📊 流量使用</p>
                <div style="margin-bottom: 8px;">
                  <div style="display: flex; justify-content: space-between; font-size: 12px; margin-bottom: 2px;">
                    <span>日流量: ${dailyUsed} MB ${dailyLimit !== '无限' ? `/ ${dailyLimit} GB` : ''}</span>
                    ${dailyLimit !== '无限' ? `<span>${dailyPercent}%</span>` : '<span>无限制</span>'}
                  </div>
                  ${dailyLimit !== '无限' ? `
                    <div style="background: #e0e0e0; height: 8px; border-radius: 4px; overflow: hidden;">
                      <div style="background: ${dailyPercent > 90 ? '#f44336' : dailyPercent > 70 ? '#ff9800' : '#4caf50'}; height: 100%; width: ${Math.min(dailyPercent, 100)}%;"></div>
                    </div>
                  ` : ''}
                </div>
                <div>
                  <div style="display: flex; justify-content: space-between; font-size: 12px; margin-bottom: 2px;">
                    <span>月流量: ${monthlyUsed} MB ${monthlyLimit !== '无限' ? `/ ${monthlyLimit} GB` : ''}</span>
                    ${monthlyLimit !== '无限' ? `<span>${monthlyPercent}%</span>` : '<span>无限制</span>'}
                  </div>
                  ${monthlyLimit !== '无限' ? `
                    <div style="background: #e0e0e0; height: 8px; border-radius: 4px; overflow: hidden;">
                      <div style="background: ${monthlyPercent > 90 ? '#f44336' : monthlyPercent > 70 ? '#ff9800' : '#4caf50'}; height: 100%; width: ${Math.min(monthlyPercent, 100)}%;"></div>
                    </div>
                  ` : ''}
                </div>
                ${trafficData.isSuspended ? '<p style="color: #f44336; font-size: 12px; margin-top: 5px;">⚠️ 流量已超限,服务已暂停</p>' : ''}
              </div>
            `;
          }
        } catch (trafficError) {
          console.log('加载流量失败:', trafficError);
        }

        html += `
          <div style="border: 1px solid #ddd; padding: 12px; margin-bottom: 15px; border-radius: 4px; background: #f9f9f9;">
            <p><strong>订阅状态:</strong> ${statusText}</p>
            ${!sub.autoRenewEnabled ? '<p style="color: #ff9800; font-size: 12px;">⚠️ 自动续费已关闭，到期后服务将停止</p>' : ''}
            <p><strong>套餐:</strong> ${planName} (ID: ${sub.planId})</p>
            <p><strong>锁定价格:</strong> ${ethers.utils.formatUnits(sub.lockedPrice, 6)} USDC</p>
            <p><strong>到期时间:</strong> ${expiry.toLocaleString('zh-CN')}</p>
            <p style="font-size: 12px; color: #666; word-break: break-all;"><strong>VPN 身份:</strong> ${sub.identityAddress}</p>

            ${trafficHtml}

            <div style="margin-top: 10px; padding-top: 10px; border-top: 1px dashed #ccc;">
              <p style="font-size: 12px; font-weight: bold; margin-bottom: 5px;">变更套餐:</p>
              <select id="changePlan_${sub.identityAddress}" style="display:inline-block; width:200px; padding:4px; font-size: 12px;">
                ${availablePlans.map(p => `<option value="${p.planId}">${p.name}</option>`).join('')}
              </select>
              <label style="font-size: 12px; margin-left: 8px;">
                <input type="checkbox" id="changeYearly_${sub.identityAddress}" style="width: auto; margin: 0;">
                按年
              </label>

              <div style="margin-top: 6px;">
                <button onclick="doUpgrade('${sub.identityAddress}')" class="btn" style="background:#28a745; padding:6px 12px; font-size:12px;">立即升级</button>
                <button onclick="doDowngrade('${sub.identityAddress}')" class="btn" style="background:#ffc107; color:#000; padding:6px 12px; font-size:12px;">下周期降级</button>
                <button onclick="doCancelChange('${sub.identityAddress}')" class="btn" style="background:#17a2b8; padding:6px 12px; font-size:12px;">取消待生效变更</button>
              </div>
            </div>
            <button onclick="cancelSubscription('${sub.identityAddress}')" style="margin-top: 10px; padding: 6px 12px; background: #dc3545; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 12px;">取消订阅</button>
          </div>
        `;
      }

      statusEl.innerHTML = html;
    } else {
      statusEl.innerHTML = '<p style="color: #666;">暂无订阅</p>';
    }
  } catch (error) {
    console.error('加载订阅失败:', error);
    document.getElementById('subStatus').textContent = '加载失败: ' + error.message;
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

    showStatus('第 1/2 步：签名订阅意图...', 'info');
    const intentSignature = await signer._signTypedData(domain, types, value);

    let permitSignature = null;
    if (parseInt(maxAmount) > 0) {
      showStatus('第 2/2 步：签名 USDC 授权（此后自动续费无需再次操作）...', 'info');
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
    showStatus(`订阅成功! Tx: ${result.txHash.slice(0, 10)}...`, 'success');

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
    showStatus('计算补差价...', 'info');
    const prorationResponse = await fetch(`${CONFIG.API_BASE}/subscription/proration?identityAddress=${identityAddress}&newPlanId=${newPlanId}`);
    const prorationData = await prorationResponse.json();

    if (!prorationData.success) {
      throw new Error(prorationData.error || '计算补差价失败');
    }

    const prorationAmount = (prorationData.prorationAmount / 1e6).toFixed(2);
    if (!confirm(`升级需要补差价 ${prorationAmount} USDC,确认继续?`)) {
      return;
    }

    const nonceRes = await fetch(`${CONFIG.API_BASE}/intent-nonce?address=${userAddress}`);
    const nonce = (await nonceRes.json()).nonce;
    const deadline = Math.floor(Date.now() / 1000) + 3600;

    const maxAmount = (100 * 1e6).toString();

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

    showStatus('提交升级交易...', 'info');
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

  if (!confirm('降级将在下个订阅周期生效,确认继续?')) {
    return;
  }

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
    setTimeout(refresh, 2000);
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
    setTimeout(refresh, 2000);
  } catch(e) {
    showStatus('撤销失败: ' + e.message, 'error');
  }
}

// 取消订阅
async function cancelSubscription(identityAddress) {
  console.log('[DEBUG] cancelSubscription 开始, identityAddress:', identityAddress);
  if (!confirm(`确定取消该订阅吗? 这将停止自动续费`)) {
    console.log('[DEBUG] 用户取消了确认对话框');
    return;
  }
  try {
    console.log('[DEBUG] 获取 nonce...');
    const nonceResponse = await fetch(`${CONFIG.API_BASE}/cancel-nonce?address=${userAddress}`);
    const { nonce } = await nonceResponse.json();
    console.log('[DEBUG] nonce:', nonce);

    const domain = { name: 'VPNSubscription', version: '2', chainId: CONFIG.CHAIN_ID, verifyingContract: CONFIG.CONTRACT_ADDRESS };
    const types = { CancelIntent: [ { name: 'user', type: 'address' }, { name: 'identityAddress', type: 'address' }, { name: 'nonce', type: 'uint256' } ] };
    const value = { user: userAddress, identityAddress, nonce: parseInt(nonce) };

    console.log('[DEBUG] 签名数据...');
    const signature = await signer._signTypedData(domain, types, value);
    console.log('[DEBUG] 签名完成');

    showStatus('提交取消请求...', 'info');
    console.log('[DEBUG] 发送取消请求到后端...');
    const response = await fetch(`${CONFIG.API_BASE}/subscription/cancel`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ userAddress, identityAddress, nonce, signature })
    });
    console.log('[DEBUG] 后端响应状态:', response.status, response.ok);

    if (!response.ok) {
      console.log('[DEBUG] 响应不成功，解析错误数据...');
      const errorData = await response.json();
      console.log('[DEBUG] 错误数据:', errorData);
      console.log('[DEBUG] 错误消息:', errorData.error);
      console.log('[DEBUG] 检查是否包含 "already cancelled":', errorData.error && errorData.error.includes('already cancelled'));

      // 检查是否是"已经取消"的错误
      if (errorData.error && errorData.error.includes('already cancelled')) {
        console.log('[DEBUG] 检测到已取消错误，显示友好提示');
        showStatus('该订阅的自动续费已经关闭，无需重复取消。', 'info');
        setTimeout(refresh, 2000);
        return;
      } else {
        console.log('[DEBUG] 其他错误，抛出异常');
        throw new Error(errorData.error);
      }
    } else {
      console.log('[DEBUG] 取消成功');
      const result = await response.json();

      // 检查是否是预检查发现已取消的情况
      if (result.alreadyCancelled) {
        console.log('[DEBUG] 后端预检查发现已取消');
        showStatus('该订阅的自动续费已经关闭，无需重复取消。', 'info');
      } else {
        showStatus('订阅已取消。如需彻底撤销 USDC 授权，请访问 revoke.cash 或在钱包中将合约授权归零。', 'info');
      }
    }

    setTimeout(refresh, 2000);
  } catch (error) {
    console.log('[DEBUG] catch 块捕获错误:', error);
    showStatus('取消失败: ' + error.message, 'error');
  }
}

async function cancel() { showStatus('请在订阅列表中点击"取消订阅"按钮', 'error'); }
async function refresh() {
  showStatus('刷新中...', 'info');
  await Promise.all([loadBalance(), loadSubscription()]);
  showStatus('刷新完成', 'success');
  setTimeout(() => { document.getElementById('status').classList.add('hidden'); }, 2000);
}

