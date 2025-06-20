// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract FantasySportsPredictionMarket {
    address public owner;
    uint256 public marketCounter;
    uint256 public constant PLATFORM_FEE = 5; // 5% platform fee
    
    enum MarketStatus { Active, Resolved, Cancelled }
    enum Outcome { TeamA, TeamB, Draw }
    
    struct Market {
        uint256 id;
        string description;
        string teamA;
        string teamB;
        uint256 endTime;
        MarketStatus status;
        Outcome result;
        uint256 totalStakeTeamA;
        uint256 totalStakeTeamB;
        uint256 totalStakeDraw;
        uint256 totalPool;
        bool feesCollected;
    }
    
    struct Prediction {
        address predictor;
        uint256 marketId;
        Outcome predictedOutcome;
        uint256 stakeAmount;
        bool claimed;
    }
    
    mapping(uint256 => Market) public markets;
    mapping(uint256 => mapping(address => Prediction)) public predictions;
    mapping(uint256 => address[]) public marketPredictors;
    mapping(address => uint256[]) public userMarkets;
    
    event MarketCreated(uint256 indexed marketId, string description, string teamA, string teamB, uint256 endTime);
    event PredictionMade(uint256 indexed marketId, address indexed predictor, Outcome outcome, uint256 amount);
    event MarketResolved(uint256 indexed marketId, Outcome result);
    event RewardsClaimed(uint256 indexed marketId, address indexed predictor, uint256 amount);
    event MarketCancelled(uint256 indexed marketId);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier marketExists(uint256 _marketId) {
        require(_marketId < marketCounter, "Market does not exist");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        marketCounter = 0;
    }
    
    /**
     * @dev Creates a new prediction market for a fantasy sports match
     * @param _description Description of the match/event
     * @param _teamA Name of team A
     * @param _teamB Name of team B
     * @param _durationHours Duration in hours from now when market closes
     */
    function createMarket(
        string memory _description,
        string memory _teamA,
        string memory _teamB,
        uint256 _durationHours
    ) external onlyOwner {
        require(_durationHours > 0, "Duration must be greater than 0");
        require(bytes(_description).length > 0, "Description cannot be empty");
        require(bytes(_teamA).length > 0, "Team A name cannot be empty");
        require(bytes(_teamB).length > 0, "Team B name cannot be empty");
        
        uint256 endTime = block.timestamp + (_durationHours * 1 hours);
        
        markets[marketCounter] = Market({
            id: marketCounter,
            description: _description,
            teamA: _teamA,
            teamB: _teamB,
            endTime: endTime,
            status: MarketStatus.Active,
            result: Outcome.TeamA, // Default, will be set when resolved
            totalStakeTeamA: 0,
            totalStakeTeamB: 0,
            totalStakeDraw: 0,
            totalPool: 0,
            feesCollected: false
        });
        
        emit MarketCreated(marketCounter, _description, _teamA, _teamB, endTime);
        marketCounter++;
    }
    
    /**
     * @dev Allows users to make predictions on a market outcome
     * @param _marketId ID of the market to predict on
     * @param _outcome Predicted outcome (0: TeamA, 1: TeamB, 2: Draw)
     */
    function makePrediction(uint256 _marketId, Outcome _outcome) 
        external 
        payable 
        marketExists(_marketId) 
    {
        Market storage market = markets[_marketId];
        require(market.status == MarketStatus.Active, "Market is not active");
        require(block.timestamp < market.endTime, "Market has ended");
        require(msg.value > 0, "Stake amount must be greater than 0");
        require(predictions[_marketId][msg.sender].stakeAmount == 0, "Already predicted on this market");
        
        // Record the prediction
        predictions[_marketId][msg.sender] = Prediction({
            predictor: msg.sender,
            marketId: _marketId,
            predictedOutcome: _outcome,
            stakeAmount: msg.value,
            claimed: false
        });
        
        // Update market totals
        if (_outcome == Outcome.TeamA) {
            market.totalStakeTeamA += msg.value;
        } else if (_outcome == Outcome.TeamB) {
            market.totalStakeTeamB += msg.value;
        } else {
            market.totalStakeDraw += msg.value;
        }
        
        market.totalPool += msg.value;
        marketPredictors[_marketId].push(msg.sender);
        userMarkets[msg.sender].push(_marketId);
        
        emit PredictionMade(_marketId, msg.sender, _outcome, msg.value);
    }
    
   
    function resolveMarket(uint256 _marketId, Outcome _result) 
        external 
        onlyOwner 
        marketExists(_marketId) 
    {
        Market storage market = markets[_marketId];
        require(market.status == MarketStatus.Active, "Market is not active");
        require(block.timestamp >= market.endTime, "Market has not ended yet");
        
        market.status = MarketStatus.Resolved;
        market.result = _result;
        
        // Collect platform fees
        if (!market.feesCollected && market.totalPool > 0) {
            uint256 platformFee = (market.totalPool * PLATFORM_FEE) / 100;
            payable(owner).transfer(platformFee);
            market.feesCollected = true;
        }
        
        emit MarketResolved(_marketId, _result);
    }
    
    /**
     * @dev Allows users to claim their rewards from resolved markets
     * @param _marketId ID of the resolved market
     */
    function claimRewards(uint256 _marketId) external marketExists(_marketId) {
        Market storage market = markets[_marketId];
        require(market.status == MarketStatus.Resolved, "Market is not resolved yet");
        
        Prediction storage prediction = predictions[_marketId][msg.sender];
        require(prediction.stakeAmount > 0, "No prediction found");
        require(!prediction.claimed, "Rewards already claimed");
        require(prediction.predictedOutcome == market.result, "Incorrect prediction");
        
        // Calculate winning pool and user's share
        uint256 winningPool;
        if (market.result == Outcome.TeamA) {
            winningPool = market.totalStakeTeamA;
        } else if (market.result == Outcome.TeamB) {
            winningPool = market.totalStakeTeamB;
        } else {
            winningPool = market.totalStakeDraw;
        }
        
        require(winningPool > 0, "No winning stakes found");
        
        // Calculate rewards after platform fee
        uint256 totalPoolAfterFees = market.totalPool - ((market.totalPool * PLATFORM_FEE) / 100);
        uint256 userReward = (prediction.stakeAmount * totalPoolAfterFees) / winningPool;
        
        prediction.claimed = true;
        payable(msg.sender).transfer(userReward);
        
        emit RewardsClaimed(_marketId, msg.sender, userReward);
    }
    
    // View functions
    function getMarket(uint256 _marketId) external view returns (Market memory) {
        return markets[_marketId];
    }
    
    function getUserPrediction(uint256 _marketId, address _user) external view returns (Prediction memory) {
        return predictions[_marketId][_user];
    }
    
    function getUserMarkets(address _user) external view returns (uint256[] memory) {
        return userMarkets[_user];
    }
    
    function getMarketPredictors(uint256 _marketId) external view returns (address[] memory) {
        return marketPredictors[_marketId];
    }
    
    function calculatePotentialReward(uint256 _marketId, Outcome _outcome, uint256 _stakeAmount) 
        external 
        view 
        returns (uint256) 
    {
        Market storage market = markets[_marketId];
        if (market.totalPool == 0) return _stakeAmount;
        
        uint256 outcomePool;
        if (_outcome == Outcome.TeamA) {
            outcomePool = market.totalStakeTeamA + _stakeAmount;
        } else if (_outcome == Outcome.TeamB) {
            outcomePool = market.totalStakeTeamB + _stakeAmount;
        } else {
            outcomePool = market.totalStakeDraw + _stakeAmount;
        }
        
        uint256 totalPoolAfterFees = (market.totalPool + _stakeAmount) - (((market.totalPool + _stakeAmount) * PLATFORM_FEE) / 100);
        return (_stakeAmount * totalPoolAfterFees) / outcomePool;
    }
    
    // Emergency functions
    function cancelMarket(uint256 _marketId) external onlyOwner marketExists(_marketId) {
        Market storage market = markets[_marketId];
        require(market.status == MarketStatus.Active, "Market is not active");
        
        market.status = MarketStatus.Cancelled;
        
        // Refund all predictors
        address[] memory predictors = marketPredictors[_marketId];
        for (uint256 i = 0; i < predictors.length; i++) {
            address predictor = predictors[i];
            Prediction storage prediction = predictions[_marketId][predictor];
            if (prediction.stakeAmount > 0 && !prediction.claimed) {
                prediction.claimed = true;
                payable(predictor).transfer(prediction.stakeAmount);
            }
        }
        
        emit MarketCancelled(_marketId);
    }
    
    function emergencyWithdraw() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
    
    // Fallback functions
    receive() external payable {}
    fallback() external payable {}
}
