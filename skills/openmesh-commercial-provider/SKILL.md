---
name: openmesh-commercial-provider
description: Use when designing or implementing the commercial-provider path for OpenMesh V2, including chain registry discovery, supplier metadata, user wallets, signer sessions, x402 automatic payments, bucket renewal, supplier receipts, or sing-box data-plane integration for paid provider switching.
---

# OpenMesh Commercial Provider

Use this skill only for the paid supplier path in OpenMesh V2.

This skill is narrower than `$openmesh-v2-openrouter` and should be preferred when the task is specifically about:

- chain-based provider discovery
- supplier metadata and signer sets
- wallet / signer session behavior
- x402 small automatic payments
- free bucket and paid bucket renewal
- payment receipts and usage receipts
- supplier-side hot-path behavior
- sing-box data-plane identity, metering, and stop/resume for paid sessions

## Required reading

Always read:

- `openmesh-apple/docs/v2/03-V2-需求规格说明书.md`
- `openmesh-apple/docs/v2/04-V2-总体架构设计.md`
- `openmesh-apple/docs/v2/05-V2-详细技术设计.md`
- `openmesh-apple/docs/v2/06-V2-数据模型与安全设计.md`
- `openmesh-apple/docs/v2/08-V2-测试策略与验收标准.md`
- `openmesh-apple/docs/v2/10-AI-执行约束与代码一致性规则.md`

## Core invariants

Never weaken these:

- Users discover commercial providers from chain registry.
- Users pay suppliers directly in USDC.
- The platform does not become the central ledger.
- Commercial renewal happens before bucket exhaustion.
- Hot path is `402 -> bounded auto-sign -> verify -> immediately allow next bucket`.
- Chain reconciliation is asynchronous and not the allow gate.
- Wallet is self-custodied and signer-session based.
- Receipts are stored on both client and supplier sides.

## Default commercial model

Unless the task explicitly changes it, assume:

- free bucket: `40MB`
- paid bucket: `40MB`
- pre-renew threshold: remaining `5MB` or `20%`
- supplier signs `PaymentReceipt`
- supplier signs `UsageReceipt`
- platform fee is collected when supplier withdraws, not on user hot path

## Design workflow

### 1. Identify the hot path

State whether the task touches:

- provider discovery
- wallet unlock / signer session
- x402 request / response flow
- pre-renew threshold logic
- receipt generation / recovery
- sing-box metering / stop-resume

### 2. Preserve the payment model

Commercial work must keep the distinction between:

- user payment hot path
- supplier-side asynchronous reconciliation
- later withdrawal / platform fee flow

Do not merge them into one step.

### 3. Preserve wallet safety

Preferred wallet model:

1. encrypted wallet blob on disk
2. device-bound wrapping key
3. plaintext key only in memory during signer session
4. bounded auto-signing only while session is active

### 4. Preserve data-plane boundaries

`sing-box` may do:

- user/session authentication
- traffic metering
- stop/resume

`sing-box` may not become:

- the final commercial ledger
- the provider registry
- the receipt truth source

## Review checklist

Before finalizing, verify:

- provider discovery is still chain-based
- a supplier can still offer a free bucket first
- renewals still trigger before exhaustion
- successful payment still allows the next bucket immediately
- no step waits for chain balance polling
- signer session still enforces single-payment and daily-payment caps
- receipts are still recoverable from either side

## Output requirements

For any design or implementation response, explicitly state:

1. what part of the commercial path changed
2. whether hot path changed
3. whether signer-session safety changed
4. whether receipt semantics changed
5. whether supplier withdrawal / platform fee semantics changed

## Done criteria

Commercial-provider work is not done unless:

- the hot path remains bounded and automatic
- signer-session safety remains intact
- receipts remain dual-sided and recoverable
- no centralized platform ledger was introduced
- the change is consistent with docs/v2
