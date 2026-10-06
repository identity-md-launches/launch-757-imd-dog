# IMD DOG (IMDOG)

A fixed-supply ERC-20 implemented in `src/IMDOG.sol:IMDOG` using the vendored
OpenZeppelin Contracts v5.1.0 ERC-20 implementation.

## Token and deployment parameters

| Parameter | Value |
| --- | --- |
| Name | `IMD DOG` |
| Symbol | `IMDOG` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in minor units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`; encoded argument bytes `0x`) |
| Constructor value | `0` |
| Initial recipient | Constructor `msg.sender` |
| Contract artifact | `out/IMDOG.sol/IMDOG.json` |
| Solidity | `0.8.26` |
| EVM target | `cancun` |
| Optimizer | Enabled, 200 runs |
| Bytecode metadata hash | `none` |

The constructor mints the entire supply once. Deploying with `new IMDOG()` from
a factory gives that factory the entire supply, even when someone else called the
factory. A direct deployment gives it to the account creating the contract.
There is no initializer or subsequent setup call. Deploy this concrete contract,
not a proxy. A local CREATE2 test checks both the predicted address and allocation.

The network deployer can use the artifact's creation bytecode with no appended
arguments. For CREATE2, the factory address and salt determine the address along
with that bytecode; neither is a token constructor parameter. Chain, factory,
salt, paired currency, pool settings, opening valuation and remainder recipient
were not supplied and must be selected by the network's launch process. This
project does not prescribe those values or supply a launch manifest.

## Behavior and assumptions

The request is interpreted as an ordinary transferable ERC-20 with no transfer
tax, burn, rebase, vesting, cap per wallet or transfer restriction. Transfers and
delegated transfers deliver exactly the specified amount. Zero-value transfers
between nonzero addresses are valid and emit `Transfer`. Transfers to the zero
address and approvals to a zero spender revert. Insufficient balances and
allowances revert atomically with ERC-6093 errors.

`approve` replaces an existing allowance. Finite allowances decrease on
`transferFrom`; `type(uint256).max` is an unlimited allowance and stays unchanged.
OpenZeppelin v5 does not emit `Approval` when `transferFrom` spends an allowance;
clients should query `allowance` for the current value. Use bounded approvals
where possible. When changing an existing nonzero allowance, holders should
revoke it first and wait for confirmation before granting a replacement to
reduce the standard ERC-20 approval race.

There is no owner, mint authority, external burn function, pause, blacklist,
seizure, upgrade, permit, recipient callback or external call in token operations.
The deployer has the same transfer and allowance rules as every other holder.
Supply remains fixed for the lifetime of the deployed instance.

## Local verification

With Foundry and Solidity 0.8.26 available:

```sh
forge build
forge test
forge fmt --check
```

All imported Solidity dependencies and their licenses are ordinary files under
`lib/`; no dependency download, package manager or submodule is needed. Foundry
still needs the pinned compiler installed in its normal compiler cache. FFI and
filesystem cheatcode permissions are disabled. Tests use no environment
configuration, fork, RPC, wallet, broadcast or filesystem access, and each test
starts from fresh state.

The suite covers metadata, constructor allocation/event, factory deployment,
transfer/approval events, exact transfers, full and zero amounts, self-transfers,
finite/unlimited allowances, revocation, invalid addresses, insufficient funds,
unauthorized spending, rollback, absent administrative entry points, runtime
opcode restrictions, and distribution/claim accounting. Three fuzz tests use
256 cases each. A stateful invariant uses 256 sequences of 64 operations across
four actors to check supply conservation and allowance accounting.

The distribution test uses an illustrative pool allocation to check token
accounting; it does not configure production economics. The supplied protected
harness also exercises an actual Uniswap v4 pool, but requires external launch
infrastructure and environment inputs absent from this repository. These local
tests do not claim to run that integration; the network verifier must run it
with the final deployment configuration.

## Operational responsibilities

The deployer is responsible for selecting a chain supporting the configured EVM
target, reviewing the creation bytecode/settings, verifying deployed source and
metadata, and confirming total supply and the factory's initial balance. The
launch factory handles the swarm distribution, liquidity and remainder transfers;
the token constructor itself only mints to its caller.

Holders manage keys, recipients and allowances. There is no recovery authority:
tokens sent to the token contract or another contract unable to transfer them
can become permanently inaccessible, without reducing `totalSupply`. The token
does not accept ordinary native-currency transfers and has no asset rescue path.
No maintenance, administrator transaction or upkeep service is required.

Local checks are not an independent security audit. Independent adversarial
review and the network's protected integration checks remain release
responsibilities. Slither and Mythril were not run. This assignment performs no
on-chain deployment or wallet operation.
