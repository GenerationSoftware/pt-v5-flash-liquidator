# Flash Liquidators

## Uniswap V3 Flash Liquidator

`UniswapFlashLiquidation`: A Uniswap V3 swap to flash liquidate yield on PoolTogether V5.
`UniswapV2WethPairFlashLiquidator`: Instantly dump yield from Prize Vaults whose assets are Uniswap LP pairs.

## Deployments

### Optimism

`UniswapFlashLiquidation`: [`0x5927b63e88764d6250b7801ebfdeb7b6c1ac35d0`](https://optimistic.etherscan.io/address/0x5927b63e88764d6250b7801ebfdeb7b6c1ac35d0)
`UniswapV2WethPairFlashLiquidator`: [`0xC976818315b3Bd2F386e8c8adB2976a1f029a417`](https://optimistic.etherscan.io/address/0xC976818315b3Bd2F386e8c8adB2976a1f029a417)

## How to Liquidate

1. run `npm i` and `forge build`
2. set your environment vars in `.envrc`
3. run `direnv allow`
4. run `npm run liquidate:pusdce` or `npm run liquidate:pweth`

## Getting started

The easiest way to get started is by clicking the [Use this template](https://github.com/pooltogether/foundry-template/generate) button at the top right of this page.

If you prefer to go the CLI way:

```
forge init my-project --template https://github.com/pooltogether/foundry-template
```

## Development

### Installation

You may have to install the following tools to use this repository:

- [Foundry](https://github.com/foundry-rs/foundry) to compile and test contracts
- [direnv](https://direnv.net/) to handle environment variables
- [lcov](https://github.com/linux-test-project/lcov) to generate the code coverage report

Install dependencies:

```
npm i
```

### Env

Copy `.envrc.example` and write down the env variables needed to run this project.

```
cp .envrc.example .envrc
```

Once your env variables are setup, load them with:

```
direnv allow
```

### Compile

Run the following command to compile the contracts:

```
npm run compile
```

### Coverage

Forge is used for coverage, run it with:

```
npm run coverage
```

You can then consult the report by opening `coverage/index.html`:

```
open coverage/index.html
```

### Code quality

[Husky](https://typicode.github.io/husky/#/) is used to run [lint-staged](https://github.com/okonet/lint-staged) and tests when committing.

[Prettier](https://prettier.io) is used to format TypeScript and Solidity code. Use it by running:

```
npm run format
```

[Solhint](https://protofire.github.io/solhint/) is used to lint Solidity files. Run it with:

```
npm run hint
```

### CI

A default Github Actions workflow is setup to execute on push and pull request.

It will build the contracts and run the test coverage.

You can modify it here: [.github/workflows/coverage.yml](.github/workflows/coverage.yml)

For the coverage to work, you will need to setup the `MAINNET_RPC_URL` repository secret in the settings of your Github repository.
