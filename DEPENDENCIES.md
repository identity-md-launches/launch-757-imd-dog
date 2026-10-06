# Vendored dependencies

Dependencies are checked in as ordinary source files, with no submodules.
Upstream files are unmodified. No upstream test, build script or repository
configuration is required to build this project.

| Dependency | Release and pinned commit | Included files | License |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/69c8def5f222ff96f2b5beff05dfba996368aa79) | v5.1.0 / `69c8def5f222ff96f2b5beff05dfba996368aa79` | ERC20, IERC20, IERC20Metadata, Context, draft-IERC6093 and LICENSE | MIT |
| [forge-std](https://github.com/foundry-rs/forge-std/tree/77041d2ce690e692d6e03cc812b57d1ddaa4d505) | v1.9.7 / `77041d2ce690e692d6e03cc812b57d1ddaa4d505` | `src/`, LICENSE-APACHE and LICENSE-MIT | Apache-2.0 OR MIT |

Only OpenZeppelin is part of the deployed token. forge-std supports local tests.
The remappings in `remappings.txt` resolve both libraries entirely within `lib/`.
