# Test from Nightshift launchpad (TESTNS)

A community coin as a test, launched with the NIGHTSHIFT Launchpad
(getnightshift.tech/launchpad).

TESTNS is a plain, fixed-supply ERC-20. The whole supply is minted once, in the
constructor, to the deployer. There is no owner, no minter, no fee, no tax, no
transfer limit, no pause and no blacklist. After deployment nobody, including
the deployer, can change anything about it.

## Token parameters

| Parameter          | Value                                                   |
| ------------------ | ------------------------------------------------------- |
| Solidity contract  | `NightshiftTestToken` (`src/NightshiftTestToken.sol`)   |
| `name()`           | `Test from Nightshift launchpad`                        |
| `symbol()`         | `TESTNS`                                                |
| `decimals()`       | `18`                                                    |
| Total supply       | 100 TESTNS = `100000000000000000000` minor units        |
| Minted to          | `msg.sender` of the constructor, once                   |
| Constructor args   | none                                                    |
| Owner / admin      | none                                                    |
| Mint after deploy  | impossible: no mint path exists                         |
| Transfer rules     | standard ERC-20, exact amounts, no fee or limit         |

All of these are compile-time constants (`TOKEN_NAME`, `TOKEN_SYMBOL`,
`DECIMALS`, `TOTAL_SUPPLY`) and are readable on chain.

### Logo

A frog with dark skin and a hoodie, with glowing eyes. The logo is an off-chain
asset for the launchpad listing and explorers; nothing in the contract refers to
it.

## Design and assumptions

- **Implementation.** `NightshiftTestToken` inherits OpenZeppelin v5.1.0
  `ERC20` unchanged, overrides `decimals()` to return the constant 18, and mints
  `TOTAL_SUPPLY` to `msg.sender` in the constructor. No other code.
- **Deployer receives the supply.** At launch the deployer is IMD's
  ProjectFactory, which then forwards the swarm share to the MerkleDistributor,
  seeds the Uniswap v4 pool and sends the remainder to the requester. Because
  transfers are plain, every launch flow (factory to distributor, distributor to
  claimant, factory to PoolManager, trader buys and sells) moves exactly the
  amount requested. The token needs no exemptions and takes no launch addresses.
- **Fixed supply.** `_mint` is called exactly once and is not reachable after
  the constructor. `totalSupply()` can never increase. There is no `burn`
  either, so it can never decrease; tokens sent to an unreachable address are
  simply stranded.
- **No privileged hand.** The contract has no owner and no roles. Nobody can
  pause, freeze, blacklist, seize or `burnFrom`. `transferFrom` only moves
  tokens the caller has been given an allowance for by the holder.
- **No ether.** The contract has no `receive` or `fallback`, so sending ether
  to it reverts.
- **No delegatecall, callcode or selfdestruct** in the runtime (tested).
- **Compiler.** solc 0.8.26, optimizer on at 200 runs, `bytecode_hash = "none"`
  and `cbor_metadata = false` so the deployed bytes are reproducible.

## Launch (decided by the launch, not open questions)

- Chain: Ethereum mainnet (chain id 1).
- Pool pair: IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` (18 decimals).
- Pool fee 12500 (1.25%), tick spacing 60. The opening price is derived by the
  deployer from `economics.initialMarketCapWei`.
- Economics, copied into the manifest by the manifest step:
  `poolBps` 7600, `initialMarketCapWei` 25000 IMD (`25000000000000000000000`),
  `remainderTo` `0x6c4c78f2c3bdf4c4318fe305fb1c8bc1694d19b5`.
- Of the supply, 10% goes to the swarm distributor, 76% seeds the pool and
  14% goes to `remainderTo`. All of this is the factory's work after the
  constructor; the token itself allocates nothing.
- `launch.json` is written by the manifest step after this work is accepted.
  It is deliberately not in this repository. The manifest's `token.totalSupply`
  is `100000000000000000000`, `decimals` 18, `constructorArgs` empty,
  `contracts` empty (there are no application contracts).

## After launch

There is nothing to configure. The token has no owner-settable values, no
setters and no events other than the ERC-20 `Transfer` and `Approval`.

## Operational responsibilities

- **Requester.** Holds the 14% remainder at `remainderTo` and is responsible
  for that wallet's key hygiene. Publishes the logo and token metadata to the
  launchpad listing and token lists. Decides how (or whether) to distribute the
  remainder; the contract offers no vesting or lock, so any such policy is
  off-chain or in a separate contract.
- **IMD deployer and verifier.** Deploy from the attested bytecode through the
  factory, derive the opening price, open the pool, seed it and forward the
  shares. Explorer source verification of the deployed address is theirs too.
- **Nobody** can mint, pause, upgrade or recover tokens. Report a lost key or a
  mistaken transfer as unrecoverable; there is no admin to appeal to.

## Repository layout

```
foundry.toml                        compiler pins and build settings
remappings.txt                      forge-std and @openzeppelin/contracts
src/NightshiftTestToken.sol         the token
script/DeployNightshiftTestToken.s.sol  local dry-run deploy script (no env, no args)
test/NightshiftTestToken.t.sol      unit and fuzz tests
test/NightshiftTestToken.invariant.t.sol  supply-conservation invariants
test/DeployNightshiftTestToken.t.sol tests the script's deploy() directly
lib/forge-std                       vendored forge-std v1.9.7 (77041d2), src only
lib/openzeppelin-contracts          vendored OpenZeppelin v5.1.0 (69c8def), the
                                    five files ERC20 needs, plus LICENSE
```

Dependencies are committed as ordinary files, not submodules, so the project
builds offline.

## Build and test

```
forge build
forge test
forge fmt --check
```

Fuzz runs are deterministic under the verifier's seed:

```
FOUNDRY_FUZZ_SEED=0x90c32429d2de32e36b0bcf373043128be345751e6f94710082fa3e36bf91992d forge test
```

Tests read no environment variables and do not depend on the calling address,
so they pass in any order and in parallel.

### What the tests cover

Success paths: metadata, the single mint `Transfer` event, whole supply to the
deployer, exact transfers with no fee, whole-balance and zero-amount
transfers, allowance set and spend, infinite allowance not decremented,
supply conservation across chains of transfers (unit, fuzz and invariant).

Failure paths: transfer over balance, transfer from an empty account, transfer
to the zero address, `transferFrom` without or over allowance, `transferFrom`
over balance despite allowance, the deployer pulling from a holder without
allowance, sending ether, and 22 common mint/admin/freeze selectors that must
not exist for either a stranger or the deployer.

Bytecode: runtime under the EIP-170 limit with no reachable DELEGATECALL,
CALLCODE or SELFDESTRUCT.

## Security review notes

Checked against the ethskills security checklist that accompanies this task:

- No external calls, so no reentrancy surface and no need for SafeERC20 inside
  the token.
- No arithmetic beyond OpenZeppelin's checked ERC-20 accounting; no division.
- No oracle, no price, no proxy, no signature scheme, no `delegatecall`.
- Access control: none to get wrong, because there are no privileged functions.
- Input validation: zero-address sender and receiver are rejected by
  OpenZeppelin's `_update`.
- Slither detectors the verifier rejects on (`suicidal`, `arbitrary-send-erc20`,
  `unprotected-upgrade`, `uninitialized-storage`, `incorrect-shift`,
  `encode-packed-collision`): none apply; `transferFrom` is OpenZeppelin's and
  spends `msg.sender`'s allowance only.
- Tools run here: `forge build`, `forge test` (unit, fuzz, invariant),
  `forge fmt --check`. Slither and Mythril were not available on this machine.

Passing tests are not an audit. A token that will carry other people's value
should get an independent adversarial review before launch, which is the
verifier's and the requester's step, not this one.
