const {
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require("hardhat");
const chai = require("chai");
const { bn, numberToWei, stringToBytes32, encodeSqrtX96 } = require("./shared/utilities");
const expect = chai.expect;

const pe = (x) => ethers.utils.parseEther(String(x))

describe("Pool", () => {
  async function setup() {
    const [owner, otherAccounts] = await ethers.getSigners();
    const signer = owner;
    //WETH
    const compiledWETH = require("canonical-weth/build/contracts/WETH9.json")
    const WETH = await new ethers.ContractFactory(compiledWETH.abi, compiledWETH.bytecode, signer);
    // erc20 factory
    const compiledERC20 = require("@uniswap/v2-core/build/ERC20.json");
    const erc20Factory = new ethers.ContractFactory(compiledERC20.abi, compiledERC20.bytecode, signer);
    // uniswap factory
    const compiledUniswapFactory = require("./compiled/UniswapV3Factory.json");
    const UniswapFactory = await new ethers.ContractFactory(compiledUniswapFactory.abi, compiledUniswapFactory.bytecode, signer);
    const uniswapFactory = await UniswapFactory.deploy()
    // uniswap router
    const compiledUniswapv3Router = require("@uniswap/v3-periphery/artifacts/contracts/SwapRouter.sol/SwapRouter.json");
    const Uniswapv3Router = new ethers.ContractFactory(compiledUniswapv3Router.abi, compiledUniswapv3Router.bytecode, signer);
    // Derivable Pool factory
    const PoolFactory = await ethers.getContractFactory("Pool")
    
    // setup uniswap
    const usdc = await erc20Factory.deploy(numberToWei(100000000));
    const weth = await WETH.deploy();
    await uniswapFactory.createPool(usdc.address, weth.address, 500)
    const uniswapv3Router = await Uniswapv3Router.deploy(uniswapFactory.address, weth.address);
    const compiledUniswapPool = require("./compiled/UniswapV3Pool.json");
    const pairAddress = await uniswapFactory.getPool(usdc.address, weth.address, 500)
    const uniswapPair = new ethers.Contract(pairAddress, compiledUniswapPool.abi, signer);
  
    const sqrtPriceRangeRateX96 = bn(2).pow(96).mul('104880884817').div('100000000000')
    // deploy
    const baseToken0 = weth.address.toLowerCase() < usdc.address.toLowerCase()
    const pool = await PoolFactory.deploy(
      pairAddress,
      sqrtPriceRangeRateX96.toString(),
      weth.address.toLowerCase() < usdc.address.toLowerCase()
    )
    const initPriceX96 = encodeSqrtX96(baseToken0 ? 1500 : 1, baseToken0 ? 1 : 1500)
    await uniswapPair.initialize(initPriceX96)

    return {
      owner,
      pool,
      usdc,
      weth,
      uniswapPair,
      uniswapv3Router
    }
  } 

  it("Deploy", async () => {
    const {
      pool,
      usdc,
      weth,
      uniswapPair
    } = await loadFixture(setup);
    const pair = await pool.COLLATERAL_TOKEN();
    const baseToken = await pool.TOKEN_BASE();
    const quoteToken = await pool.TOKEN_QUOTE();
    expect(baseToken).to.equal(weth.address);
    expect(quoteToken).to.equal(usdc.address);
    expect(pair).to.equal(uniswapPair.address);
  })

  it("Recompose", async () => {
    const {
      pool,
      usdc,
      weth,
      uniswapPair
    } = await loadFixture(setup);
    await usdc.transfer(pool.address, '1500000')
    await weth.deposit({ value: pe(100)})
    await weth.transfer(pool.address, '1000')
    
    await pool.recompose('1000', '1500000')

    console.log(await pool.liquidityValueInQuote())
  })

  it("Liquidity value", async () => {
    const {
      pool,
      usdc,
      weth,
      uniswapPair
    } = await loadFixture(setup);
    await usdc.transfer(pool.address, '1500000')
    await weth.deposit({ value: pe(100)})
    await weth.transfer(pool.address, '1000')
    
    await pool.recompose('1000', '1500000')

    const usdcAmount = await usdc.balanceOf(uniswapPair.address)
    const wethAmount = await weth.balanceOf(uniswapPair.address)
    const expected = usdcAmount.add(wethAmount * 1500).toNumber()
    const actual = (await pool.liquidityValueInQuote()).toNumber()

    expect(expected/actual).to.closeTo(1, 0.0001)
  })

  it("Swap -> recompose", async () => {
    const {
      owner,
      pool,
      usdc,
      weth,
      uniswapv3Router
    } = await loadFixture(setup);
    await usdc.approve(uniswapv3Router.address, '100000000000')

    await usdc.transfer(pool.address, '1500000')
    await weth.deposit({ value: pe(100)})
    await weth.transfer(pool.address, '1000')
    await pool.recompose('1000', '1500000')

    await uniswapv3Router.exactOutputSingle({
      tokenIn: usdc.address, 
      tokenOut: weth.address,
      fee: 500,
      sqrtPriceLimitX96: weth.address.toLowerCase() < usdc.address.toLowerCase()
        ? bn('1461446703485210103287273052203988822378723970341')
        : bn('4295128740'),
      recipient: owner.address,
      deadline: new Date().getTime() + 100000,
      amountOut: '100',
      amountInMaximum: '1500000',
    })

    await usdc.transfer(pool.address, '1500000')
    await weth.transfer(pool.address, '1000')
    await pool.recompose('1000', '1500000')
  })
})