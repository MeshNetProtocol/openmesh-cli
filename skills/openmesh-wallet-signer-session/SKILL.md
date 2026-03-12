---
name: openmesh-wallet-signer-session
description: Use when designing or implementing OpenMesh wallet behavior, encrypted wallet storage, device-bound protection, signer sessions, auto-sign limits, unlock UX, or any x402 signing flow that touches mnemonic, private key, Keychain, Secure Enclave, or LocalAuthentication.
---

# OpenMesh Wallet Signer Session

Use this skill only for wallet and signing work in OpenMesh V2.

This skill applies to tasks involving:

- wallet creation or recovery
- mnemonic handling
- private key lifecycle
- encrypted wallet blob storage
- Keychain / Secure Enclave integration
- LocalAuthentication / Touch ID unlock
- signer session lifetime
- x402 automatic signing limits
- unlock UX for commercial provider payments

## Required reading

Always read:

- `openmesh-apple/docs/v2/03-V2-需求规格说明书.md`
- `openmesh-apple/docs/v2/06-V2-数据模型与安全设计.md`
- `openmesh-apple/docs/v2/08-V2-测试策略与验收标准.md`
- `openmesh-apple/docs/v2/09-V2-风险、兼容性与回滚方案.md`
- `openmesh-apple/docs/v2/10-AI-执行约束与代码一致性规则.md`

If the task affects commercial hot path, also read:

- `openmesh-apple/docs/v2/04-V2-总体架构设计.md`
- `openmesh-apple/docs/v2/05-V2-详细技术设计.md`

## Core invariants

Never weaken these:

- mnemonic plaintext never persists to disk
- private key plaintext never persists to disk
- plaintext signing key exists only in memory during signer session
- automatic signing is always bounded
- signer session must balance usability and safety
- official limited access and DIY must not be forced through wallet creation

## Preferred design

Default model:

1. generate a random `walletDataKey`
2. encrypt wallet material into a local blob with `walletDataKey`
3. wrap `walletDataKey` with device-bound security
4. store only encrypted materials at rest
5. unlock into memory only for an active signer session

Preferred device-bound primitives:

- Keychain
- Secure Enclave
- LocalAuthentication
- Touch ID

## Signer-session rules

Signer session should expose and enforce:

- `singlePaymentLimit`
- `dailyPaymentLimit`
- `dailySpent`
- `unlockExpiresAt`
- `unlockMethod`
- `requiresManualConfirm`

Mandatory lock triggers:

- timeout reached
- user manually locks
- app exits
- daily limit exhausted
- system security context becomes invalid

## UX rules

Good UX:

- one unlock can cover multiple small x402 payments
- supplier switching should reuse a valid signer session
- users can choose bounded auto-pay behavior in settings

Bad UX:

- prompting for password on every 402
- prompting on every supplier switch when session is still valid
- enabling unlimited background signing

## Security review checklist

Before finalizing wallet-related work, verify:

- no mnemonic plaintext is stored
- no private key plaintext is stored
- device-bound unwrap is required before signing
- memory cleanup happens on lock/timeout/exit
- auto-pay limits are enforced
- manual confirmation path exists when limits are exceeded
- the change does not accidentally force wallet usage into official limited or DIY flows

## Output requirements

For any wallet/signing design or implementation, explicitly state:

1. what is stored at rest
2. what exists only in memory
3. how device binding works
4. how signer session starts and ends
5. how auto-pay limits are enforced
6. what happens when limits are exceeded

## Done criteria

Wallet/signing work is not done unless:

- at-rest storage is encrypted
- plaintext key material is memory-only
- signer session lifecycle is explicit
- auto-pay is bounded
- fallback manual confirmation exists
- official limited and DIY remain wallet-optional
