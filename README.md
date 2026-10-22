# Muttualy Assured Destruction (MAD)

`src/MADToken.sol` — Solidity contract `MADToken`.

| Parameter | Value |
|---|---|
| name | Muttualy Assured Destruction |
| symbol | MAD |
| decimals | 18 |
| total supply | 1,000,000,000 MAD = `1000000000000000000000000000` minor units |
| constructor arguments | none |

## Behaviour and assumptions
- The whole supply is minted once, in the constructor, to `msg.sender` (the launch factory). No mint function exists; supply can only shrink, via `burn(uint256)` of the caller's own balance.
- No owner, admin, pause, blacklist, fee or tax. Transfers move exactly the stated amount, so the factory → distributor → pool flows arrive whole.
- An allowance of `type(uint256).max` is treated as infinite and not decreased.
- Transfers to the zero address revert (use `burn`).
- No libraries, no DELEGATECALL / SELFDESTRUCT.

## Deployment
Deployed by IMD's launch factory on Ethereum (chain id 1), paired with IMD; launch economics are set by the launch manifest, not by this contract. Compiler: solc 0.8.26, optimizer 200 runs, `bytecode_hash = "none"`.

## After launch
Nothing to configure. With no owner there are no operational responsibilities on-chain; the token is immutable.

## Checks
`forge build`, `forge test`, `forge fmt --check`. Tests are not an audit.
