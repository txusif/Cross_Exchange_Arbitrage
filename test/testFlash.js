const { expect, assert } = require("chai");
const { ethers } = require("hardhat");
const { fundContract } = require("../utils/utilities");

const {
  abi,
} = require("../artifacts/contracts/interfaces/IERC20.sol/IERC20.json");

const provider = waffle.provider;

describe("FlashLoan Contract", () => {
  let FLASHLOAN, BORROW_AMOUNT, FUND_AMOUNT, initialFundingHuman, txArbitrage;

  const DECIMALS = 6;

  const USDC_WHALE = "0xcffad3200574698b78f32232aa9d63eabd290703";
  const USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
  const LINK = "0x514910771AF9Ca656af840dff83E8264EcF986CA";

  const usdcInstance = new ethers.Contract(USDC, abi, provider);

  beforeEach(async () => {
    const whale_balance = await provider.getBalance(USDC);
    console.log(whale_balance);
    expect(whale_balance).not.equal("0");

    const FlashLoan = await ethers.getContractFactory("FlashLoan");
    FlashLoan = await FlashLoan.deploy();
    await FlashLoan.deployed();

    const borrowAmountHuman = "1";
    BORROW_AMOUNT = ethers.utils.parseUnits(borrowAmountHuman, DECIMALS);
    console.log(BORROW_AMOUNT);

    initialFundingHuman = "1";
    FUND_AMOUNT = ethers.utils.parseUnits(initialFundingHuman, DECIMALS);
    await fundContract(
      usdcInstance,
      USDC_WHALE,
      FlashLoan.address,
      initialFundingHuman,
      DECIMALS
    );
    console.log(FUND_AMOUNT);
  });
  describe("Arbitrage", async () => {
    it("ensures that the contract is funded.", async () => {
      const flashLoanBalance = await FLASHLOAN.getBalanceOfToken(LINK);
      console.log(flashLoanBalance);

      const flashLoanBalanceHuman = ethers.utils.formatUnits(
        flashLoanBalance,
        DECIMALS
      );
      console.log(flashLoanBalanceHuman);

      expect(Number(flashLoanBalanceHuman)).to.equal(
        Number(initialFundingHuman)
      );
    });

    it("executes arbitrage", async () => {
      txArbitrage = await FLASHLOAN.executeArbitrage(USDC, BORROW_AMOUNT);
      assert(txArbitrage);
    });
  });
});
