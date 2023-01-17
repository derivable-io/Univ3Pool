const {
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require("hardhat");
const chai = require("chai");
const { bn, numberToWei, stringToBytes32 } = require("./shared/utilities");
const expect = chai.expect;

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
    // Derivable Pool factory
    const PoolFactory = await ethers.getContractFactory("Pool")
    
    // setup uniswap
    const usdc = await erc20Factory.deploy(numberToWei(100000000));
    const weth = await WETH.deploy();
    await uniswapFactory.createPool(usdc.address, weth.address, 500)
    const pairAddress = await uniswapFactory.getPool(usdc.address, weth.address, 500)
  
    const sqrtPriceRangeRateX96 = bn(2).pow(96).mul('104880884817').div('100000000000')
    // deploy
    const pool = await PoolFactory.deploy(
      pairAddress,
      sqrtPriceRangeRateX96.toString(),
      weth.address < usdc.address
    )
    return {
      owner,
      pool,
      usdc,
      weth,
      pairAddress
    }
  } 

  it("Deploy", async () => {
    const {
      pool,
      usdc,
      weth,
      pairAddress
    } = await loadFixture(setup);
    const pair = await pool.COLLATERAL_TOKEN();
    const baseToken = await pool.TOKEN_BASE();
    const quoteToken = await pool.TOKEN_QUOTE();
    expect(baseToken).to.equal(weth.address);
    expect(quoteToken).to.equal(usdc.address);
    expect(pair).to.equal(pairAddress);
  })
})