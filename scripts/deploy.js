const { ethers } = require("hardhat");
const { verify } = require("../utils/verify");

async function main() {
    console.log("🚀 Starting Fantasy Sports Prediction Market deployment...\n");

    const [deployer] = await ethers.getSigners();
    console.log(`📋 Deploying with account: ${deployer.address}`);
    console.log(`💰 Account balance: ${ethers.utils.formatEther(await deployer.getBalance())} ETH\n`);

    // Configuration parameters
    const config = {
        // Oracle configuration
        oracleAddress: process.env.ORACLE_ADDRESS || "0x0000000000000000000000000000000000000000", // Replace with actual oracle
        
        // Market configuration
        platformFeePercentage: 250, // 2.5% (basis points)
        minBetAmount: ethers.utils.parseEther("0.01"), // 0.01 ETH minimum bet
        maxBetAmount: ethers.utils.parseEther("100"), // 100 ETH maximum bet
        
        // Timelock configuration
        minDelay: 86400, // 1 day in seconds
        
        // Token configuration (if using ERC20)
        tokenName: "Fantasy Sports Token",
        tokenSymbol: "FST",
        initialSupply: ethers.utils.parseEther("1000000"), // 1M tokens
    };

    try {
        // 1. Deploy Oracle (if not using external oracle)
        console.log("📡 Deploying Sports Oracle...");
        const SportsOracle = await ethers.getContractFactory("SportsOracle");
        const sportsOracle = await SportsOracle.deploy();
        await sportsOracle.deployed();
        console.log(`✅ SportsOracle deployed to: ${sportsOracle.address}\n`);

        // 2. Deploy Token (if using custom token)
        console.log("🪙 Deploying Fantasy Sports Token...");
        const FantasyToken = await ethers.getContractFactory("FantasyToken");
        const fantasyToken = await FantasyToken.deploy(
            config.tokenName,
            config.tokenSymbol,
            config.initialSupply
        );
        await fantasyToken.deployed();
        console.log(`✅ FantasyToken deployed to: ${fantasyToken.address}\n`);

        // 3. Deploy Market Factory
        console.log("🏭 Deploying Market Factory...");
        const MarketFactory = await ethers.getContractFactory("FantasyMarketFactory");
        const marketFactory = await MarketFactory.deploy(
            sportsOracle.address,
            config.platformFeePercentage
        );
        await marketFactory.deployed();
        console.log(`✅ MarketFactory deployed to: ${marketFactory.address}\n`);

        // 4. Deploy Main Prediction Market Contract
        console.log("🎯 Deploying Fantasy Sports Prediction Market...");
        const FantasyPredictionMarket = await ethers.getContractFactory("FantasyPredictionMarket");
        const fantasyMarket = await FantasyPredictionMarket.deploy(
            sportsOracle.address,
            marketFactory.address,
            fantasyToken.address,
            config.minBetAmount,
            config.maxBetAmount,
            config.platformFeePercentage
        );
        await fantasyMarket.deployed();
        console.log(`✅ FantasyPredictionMarket deployed to: ${fantasyMarket.address}\n`);

        // 5. Deploy Timelock Controller (for governance)
        console.log("⏰ Deploying Timelock Controller...");
        const TimelockController = await ethers.getContractFactory("TimelockController");
        const timelock = await TimelockController.deploy(
            config.minDelay,
            [deployer.address], // proposers
            [deployer.address], // executors
            deployer.address    // admin
        );
        await timelock.deployed();
        console.log(`✅ TimelockController deployed to: ${timelock.address}\n`);

        // 6. Deploy Governance Token (if implementing DAO governance)
        console.log("🗳️ Deploying Governance Token...");
        const GovernanceToken = await ethers.getContractFactory("GovernanceToken");
        const governanceToken = await GovernanceToken.deploy();
        await governanceToken.deployed();
        console.log(`✅ GovernanceToken deployed to: ${governanceToken.address}\n`);

        // 7. Deploy Governor Contract
        console.log("🏛️ Deploying Governor...");
        const Governor = await ethers.getContractFactory("FantasyGovernor");
        const governor = await Governor.deploy(
            governanceToken.address,
            timelock.address
        );
        await governor.deployed();
        console.log(`✅ Governor deployed to: ${governor.address}\n`);

        // 8. Setup initial configuration
        console.log("⚙️ Setting up initial configurations...");
        
        // Set market factory in main contract
        await fantasyMarket.setMarketFactory(marketFactory.address);
        console.log("✓ Market factory set in main contract");

        // Set main contract in factory
        await marketFactory.setMainContract(fantasyMarket.address);
        console.log("✓ Main contract set in factory");

        // Grant oracle role to deployer (temporary)
        const ORACLE_ROLE = await sportsOracle.ORACLE_ROLE();
        await sportsOracle.grantRole(ORACLE_ROLE, deployer.address);
        console.log("✓ Oracle role granted to deployer");

        // Transfer some tokens to main contract for rewards
        const rewardAmount = ethers.utils.parseEther("100000"); // 100k tokens
        await fantasyToken.transfer(fantasyMarket.address, rewardAmount);
        console.log("✓ Reward tokens transferred to main contract");

        console.log("\n🎉 Deployment completed successfully!\n");

        // Contract addresses summary
        const deploymentSummary = {
            SportsOracle: sportsOracle.address,
            FantasyToken: fantasyToken.address,
            MarketFactory: marketFactory.address,
            FantasyPredictionMarket: fantasyMarket.address,
            TimelockController: timelock.address,
            GovernanceToken: governanceToken.address,
            Governor: governor.address,
            Deployer: deployer.address,
            Network: (await ethers.provider.getNetwork()).name
        };

        console.log("📋 DEPLOYMENT SUMMARY:");
        console.log("=====================================");
        Object.entries(deploymentSummary).forEach(([key, value]) => {
            console.log(`${key.padEnd(25)}: ${value}`);
        });
        console.log("=====================================\n");

        // Save deployment addresses to file
        const fs = require('fs');
        const deploymentData = {
            ...deploymentSummary,
            timestamp: new Date().toISOString(),
            blockNumber: await ethers.provider.getBlockNumber()
        };

        fs.writeFileSync(
            `./deployments/${(await ethers.provider.getNetwork()).name}-deployment.json`,
            JSON.stringify(deploymentData, null, 2)
        );
        console.log("💾 Deployment data saved to deployments folder\n");

        // Verify contracts on block explorer (if not on localhost)
        const network = await ethers.provider.getNetwork();
        if (network.chainId !== 31337 && process.env.ETHERSCAN_API_KEY) {
            console.log("🔍 Starting contract verification...");
            
            try {
                await verify(sportsOracle.address, []);
                await verify(fantasyToken.address, [config.tokenName, config.tokenSymbol, config.initialSupply]);
                await verify(marketFactory.address, [sportsOracle.address, config.platformFeePercentage]);
                await verify(fantasyMarket.address, [
                    sportsOracle.address,
                    marketFactory.address,
                    fantasyToken.address,
                    config.minBetAmount,
                    config.maxBetAmount,
                    config.platformFeePercentage
                ]);
                await verify(timelock.address, [
                    config.minDelay,
                    [deployer.address],
                    [deployer.address],
                    deployer.address
                ]);
                await verify(governanceToken.address, []);
                await verify(governor.address, [governanceToken.address, timelock.address]);
                
                console.log("✅ All contracts verified successfully!");
            } catch (error) {
                console.log("❌ Verification failed:", error.message);
            }
        }

        // Instructions for next steps
        console.log("\n📝 NEXT STEPS:");
        console.log("1. Update frontend config with deployed addresses");
        console.log("2. Set up sports data feeds in the oracle");
        console.log("3. Create initial prediction markets");
        console.log("4. Configure governance parameters");
        console.log("5. Transfer ownership to timelock/governance\n");

        return deploymentSummary;

    } catch (error) {
        console.error("❌ Deployment failed:", error);
        throw error;
    }
}

// Helper function to create a sample market (optional)
async function createSampleMarket(fantasyMarket, sportsOracle) {
    console.log("🏈 Creating sample market...");
    
    const gameId = "NFL_2024_WEEK1_KC_VS_BAL";
    const gameTime = Math.floor(Date.now() / 1000) + 86400; // 1 day from now
    const marketData = {
        gameId: gameId,
        homeTeam: "Kansas City Chiefs",
        awayTeam: "Baltimore Ravens",
        gameTime: gameTime,
        marketType: 1, // Win/Loss market
        options: ["Chiefs Win", "Ravens Win"]
    };

    const tx = await fantasyMarket.createMarket(
        gameId,
        marketData.homeTeam,
        marketData.awayTeam,
        gameTime,
        marketData.marketType,
        marketData.options
    );
    
    await tx.wait();
    console.log("✅ Sample market created successfully!");
}

// Execute deployment
if (require.main === module) {
    main()
        .then(() => process.exit(0))
        .catch((error) => {
            console.error(error);
            process.exit(1);
        });
}

module.exports = main;
