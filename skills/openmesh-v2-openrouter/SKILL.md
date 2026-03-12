---
name: openmesh-v2-openrouter
description: Use when working on OpenMesh V2 in openmesh-apple/MeshFluxMac, especially for OpenMesh UI, official limited access, DIY/private nodes, commercial providers, wallet/signer session, x402 payment flow, provider discovery, receipts, or docs/v2 architecture updates. This skill enforces the project's OpenRouter-style, decentralized commercial architecture and the four-scenario model.
---

# OpenMesh V2 OpenRouter

Use this skill for tasks that touch:

- `openmesh-apple/MeshFluxMac`
- `openmesh-apple/docs/v2`
- OpenMesh UI and state model
- official limited access
- DIY / private nodes
- commercial provider architecture
- wallet / signer session
- x402 automatic payment
- provider discovery and receipts

## Core model

Always classify the task into one or more of these four scenarios before making changes:

1. `no-route`
2. `official-limited`
3. `commercial-provider`
4. `private-diy`

If a change spans multiple scenarios, say so explicitly and keep their boundaries separate.

## Non-negotiable architecture

These rules are project-specific and must not be weakened:

- OpenMesh is the VPN industry's OpenRouter, not an installation center.
- Commercial provider discovery comes from chain registry, not a centralized marketplace backend.
- Users pay suppliers directly in USDC; the platform does not become the central ledger.
- Official limited access and DIY/private nodes must remain usable without a wallet.
- Commercial hot path is `pre-renew before exhaustion -> x402 auto payment -> immediate allow next bucket`.
- Chain watchers are for asynchronous reconciliation only, never the hot-path gate.
- Wallet is user-owned. Do not redesign it as a platform account.
- Private key plaintext may exist only in memory during a signer session.

## Required reading

Load only the docs relevant to the scenario.

### For all OpenMesh V2 work

Read:

- `openmesh-apple/docs/v2/00-README.md`
- `openmesh-apple/docs/v2/10-AI-执行约束与代码一致性规则.md`

### For commercial provider work

Also read:

- `openmesh-apple/docs/v2/03-V2-需求规格说明书.md`
- `openmesh-apple/docs/v2/04-V2-总体架构设计.md`
- `openmesh-apple/docs/v2/05-V2-详细技术设计.md`
- `openmesh-apple/docs/v2/06-V2-数据模型与安全设计.md`
- `openmesh-apple/docs/v2/07-V2-实施计划与迁移步骤.md`
- `openmesh-apple/docs/v2/08-V2-测试策略与验收标准.md`

### For official limited access

Also read:

- `openmesh-apple/docs/v2/01-V2-升级背景与范围说明.md`
- `openmesh-apple/docs/v2/03-V2-需求规格说明书.md`

### For private DIY

Also read:

- `openmesh-apple/docs/v2/03-V2-需求规格说明书.md`
- `openmesh-apple/docs/v2/07-V2-实施计划与迁移步骤.md`

## Workflow

### 1. Classify the scenario

Start by stating:

- which of the four scenarios are affected
- whether the task changes hot-path commercial behavior
- whether it affects official limited access or DIY independence

### 2. Check the existing code first

When the task changes implementation, inspect current code before proposing architecture changes.

At minimum, inspect these files if relevant:

- `openmesh-apple/MeshFluxMac/OpenMeshMacApp.swift`
- `openmesh-apple/MeshFluxMac/views/openmesh/OpenMeshView.swift`
- `openmesh-apple/MeshFluxMac/views/openmesh/OpenMeshTopBarView.swift`
- `openmesh-apple/MeshFluxMac/views/openmesh/OpenMeshSupplierListView.swift`
- `openmesh-apple/MeshFluxMac/views/openmesh/OpenMeshDIYView.swift`
- `openmesh-apple/MeshFluxMac/core/VPNController.swift`
- `openmesh-apple/MeshFluxMac/core/VPNManager.swift`

### 3. Preserve the right boundaries

#### If `official-limited`

- Keep it simple.
- It may continue to use the simple single-node sing-box path.
- Do not force wallet creation.
- Do not pull in full commercial receipt logic unless explicitly needed.

#### If `private-diy`

- Do not require wallet or payment.
- Do not let commercial failures disable this path.
- Keep it parallel to commercial providers, not subordinate to them.

#### If `commercial-provider`

Must preserve:

- chain-based provider discovery
- signer session model
- x402 automatic payment
- bucket-based pre-renewal
- provider-signed receipts
- immediate allow after payment verification

Must avoid:

- centralized balance ledger
- platform-custodied funds
- waiting for chain watcher confirmation before allowing the next bucket
- redesigning the experience as manual purchase/install flow

## Commercial-provider checklist

When touching commercial-provider behavior, verify all of these:

- Provider discovery still comes from chain registry.
- The user wallet is still self-custodied.
- Signer session still limits single-payment and daily-payment amounts.
- Private keys are still plaintext only in memory.
- Renewal happens before bucket exhaustion.
- Payment verification is sufficient to continue service.
- Receipts are stored on both client and provider sides.
- The change does not break official limited access or DIY.

## Wallet / signer-session rules

Preferred design:

1. Encrypt wallet material into a blob.
2. Protect the blob key with device-bound security.
3. Unlock once into a signer session.
4. Allow bounded automatic x402 signing during that session.
5. Destroy plaintext key material on timeout, manual lock, app exit, or limit exhaustion.

Acceptable device-bound security includes:

- Keychain
- Secure Enclave
- LocalAuthentication / Touch ID

Never:

- store mnemonic plaintext
- store private key plaintext on disk
- allow unbounded automatic payments

## Output requirements

When proposing or implementing changes, always state:

1. which scenario(s) are affected
2. whether commercial hot path changed
3. whether official limited access remains simple and usable
4. whether DIY/private remains wallet-independent
5. whether signer session safety still holds

## Done criteria

A task is not complete unless all are true:

- The affected scenario is explicitly identified.
- The change follows the docs/v2 architecture for that scenario.
- Commercial hot path remains `pre-renew -> x402 -> immediate allow`.
- Official limited access and DIY still work as independent paths.
- Wallet safety boundaries are still intact.
- Tests or validation gaps are called out explicitly if not run.
