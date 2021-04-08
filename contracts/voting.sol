
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";


interface IERC20Token {
    function totalSupply() external view returns (uint256);
    function balanceOf(address _owner) external view returns (uint256);
    function setLock(address user,uint256 time) external returns(bool);
    function getLock(address user) external view returns(uint256);
}




contract Governance  is Ownable{
    
    IERC20Token public tokenContract; 

  
    uint256 public closeTime = 24 hours;   // timestamp when votes will close
    
    //2 decimals
    uint256 public expeditedLevel = 500; // user who has this percentage of token can suggest change
    
    uint256 public absoluteLevel = 5000; // this percentage of participants voting power considering as Absolute Majority
    
    uint256 public ballotIds;
    uint256 public rulesIds;
    
    enum Vote {None, Yea, Nay}
    enum Status {New, Canceled, Approved, Rejected, Pending}
    
    struct Rule {
        address contr;      // contract address which have to be triggered
        uint8 majority;  // require more than this percentage of participants voting power (in according tokens).
        string funcAbi;     // function ABI (ex. "transfer(address,uint256)")
    }
    

    struct Ballot {
        uint256 closeVote; // timestamp when vote will close
        uint256 ruleId; // rule which edit
        bytes args; // ABI encoded arguments for proposal which is required to call appropriate function
        Status status;
        address creator;    // wallet address of ballot creator.
        uint256 yea;  // YEA votes according communities (tokens)
        uint256 nay;
        uint256 totalVotes;  // The total voting power od all participant according communities (tokens)
    }
    
    mapping(uint256 => Ballot) public ballots;
    mapping(uint256 => Rule) public rules;
    mapping(address => mapping(uint256 => bool)) public voted;
    mapping(address => mapping(uint256 => uint)) public yays;
    

    uint256 public circulationSupply;   // Circulation Supply of according tokens
    uint256 public circulationSupplyUpdated; // timestamp when Circulation Supply was updated
    
    address[] public excluded;
    
    
    event AddRule(address indexed contractAddress, string funcAbi, uint8 majorMain);
    event ApplyBallot(uint256 indexed ruleId, uint256 indexed ballotId);

    
    constructor()  {
        rules[0] = Rule(address(this),50,"addRule(address,uint8,string)");
    }
    
     /**
     * @dev Add new rule - function that call target contract to change setting.
     * @param contr The contract address which have to be triggered
     * @param majority The majority level (%) for the tokens 
     * @param funcAbi The function ABI (ex. "transfer(address,uint256)")
     */
    function addRule(
        address contr,
        uint8  majority,
        string memory funcAbi
        ) external onlyOwner {
        require(contr != address(0), "Zero address");
        rulesIds +=1;
        rules[rulesIds] = Rule(contr, majority, funcAbi);
        emit AddRule(contr, funcAbi, majority);
    }
    
    /**
     * @dev Add addresses to excluded list
     * @param wallet List of addresses to add
     */
    function addExcluded(address[] memory wallet) external onlyOwner {
        for (uint i = 0; i < wallet.length; i++) {
            excluded.push(wallet[i]);
        }
    }
    
     /**
     * @dev Remove addresses from excluded list
     * @param wallet The address to remove
     */
    function removeExcluded(address wallet) external onlyOwner {
        require(wallet != address(0),"Zero address not allowed");
        uint len = excluded.length;
        for (uint i = 0; i < len; i++) {
            if (excluded[i] == wallet) {
                excluded[i] = excluded[len-1];
                excluded.pop();
            }
        }
    }
    
    /**
     * @dev Set percentage of participants voting power considering as Absolute Majority
     * @param level The percentage
     */
    function setAbsoluteLevel(uint256 level) external onlyOwner {
        require(level > 5000 && level <= 10000, "Wrong level");
        absoluteLevel = level;
    }
    
    /**
     * @dev Set close time for voting 
     * @param time The epoch time
    */
    function setCloseTime(uint256 time) external onlyOwner {
        closeTime = time;
    }

    /**
     * @dev Set percentage of total circulation that allows user to expedite proposal
     * @param level The percentage
     */
    function setExpeditedLevel(uint256 level) external onlyOwner {
        require(level >= 1 && level <= 10000, "Wrong level");
        expeditedLevel = level;
    }
    
    /**
     * @dev Get rules details.
     * @param ruleId The rules index
     * @return contr The contract address
     * @return majority The level of majority in according tokens
     * @return funcAbi The function Abi (ex. "transfer(address,uint256)")
    */
    function getRule(uint256 ruleId) external view
        returns(address contr,
        uint8 majority,
        string memory funcAbi)
    {
        Rule storage r = rules[ruleId];
        return (r.contr, r.majority, r.funcAbi);
    }
    
    function _getVotingPower(address voter) internal view
        returns(uint256 votingPower)
    {
        return tokenContract.balanceOf(voter);
    }
    
    function _checkMajority(uint8 majority,uint256 _ballotId) internal view returns(bool){
        Ballot memory b = ballots[_ballotId];
        uint256 totalVotes =  b.yea * 10000 / circulationSupply ;
        if(totalVotes >= absoluteLevel){
            return true;
        }else if(b.closeVote >= block.timestamp){
            totalVotes = b.yea * 10000 / b.totalVotes;
            if(totalVotes > majority){
                return true;
            }
            
        }
        return false;
    }
    
     /**
     * @dev Calculate Circulation Supply = Total supply - sum(excluded addresses balance)
     */
    function _getCirculation() internal {
        uint256 total;
        
        uint len = excluded.length;
        for (uint j = 0; j < len; j++) {
            total += tokenContract.balanceOf(excluded[j]);
        }
        uint256 t = tokenContract.totalSupply();
        require(t >= total, "Total Supply less then accounts balance");
        circulationSupply = t - total;
        circulationSupplyUpdated = block.timestamp;  // timestamp when circulationSupply updates
        
    }
    
    
    function vote(uint256 _ballotId,uint yay) external returns (bool){
        require(_ballotId <= rulesIds,"Wrong rule ID");
        require(voted[msg.sender][_ballotId] == false,"already voted");
        
        Ballot storage b = ballots[_ballotId];
        require(b.closeVote >= block.timestamp,"voting closed");
        uint256 power = _getVotingPower(msg.sender);
        
        if(yay == 1){
            b.yea += power;    
        }else{
            b.nay += power;
        }
        
        b.totalVotes += power;
        
        uint256 userLock = tokenContract.getLock(msg.sender);
        
        if(b.closeVote > userLock ){
            tokenContract.setLock(msg.sender,b.closeVote);
        }
        
        bool majority = _checkMajority(rules[b.ruleId].majority,_ballotId);
        voted[msg.sender][_ballotId] = true;
        yays[msg.sender][_ballotId] = yay;
        if(majority){
            b.status = Status.Approved;
            _executeBallot(_ballotId);
        }
        return true;
        
    }
    
    
    function releaseToken() external returns (bool){
        
        uint256 _tmpBallot = ballotIds;
        while(true){
            if(ballots[_tmpBallot].closeVote <= block.timestamp && voted[msg.sender][_tmpBallot]){
                tokenContract.setLock(msg.sender,ballots[_tmpBallot].closeVote);
                break;
            }
            _tmpBallot -= 1;
        } 
        return true;
    }
    
    function unVote(uint256 _ballotId) external returns (bool){
        
        require(voted[msg.sender][_ballotId],"not voted");
        uint256 power = _getVotingPower(msg.sender);
        Ballot storage b = ballots[_ballotId];
        require(b.closeVote >= block.timestamp,"voting closed");
        
        uint yay = yays[msg.sender][_ballotId];
    
        if(yay == 1){
            b.yea -= power;    
        }else{
            b.nay -= power;
        }
        
        b.totalVotes -= power;
        
        uint256 userLock = tokenContract.getLock(msg.sender);
        
        if(b.closeVote == userLock){
            uint256 _tmpBallot = _ballotId - 1;
            while(true){
                if(_tmpBallot == 0){
                    tokenContract.setLock(msg.sender,0);
                    break;
                }else if(voted[msg.sender][_tmpBallot]){
                    tokenContract.setLock(msg.sender,ballots[_tmpBallot].closeVote);
                    break;
                }
                _tmpBallot -= 1;
                
            }
        }
        
        return true;
    }
    
    function createBallot(uint256 ruleId, bytes memory args) external {
        
        require(ruleId <= rulesIds,"Wrong rule ID");
        Rule storage r = rules[ruleId];
        uint256 power = _getVotingPower(msg.sender);
        _getCirculation();
        uint256 percentage = power * 10000 / circulationSupply;
        require(percentage >= expeditedLevel,"require expedited Level to suggest change");
        ballotIds += 1;
        Ballot storage b = ballots[ballotIds];
        b.ruleId = ruleId;
        b.args = args;
        b.creator = msg.sender;
        b.yea = power;
        b.totalVotes = power;
        b.closeVote = block.timestamp + closeTime;
        voted[msg.sender][ballotIds] = true;
        yays[msg.sender][ballotIds] = 1;
        
        bool majority = _checkMajority(r.majority,ballotIds);
        
        if(majority){
            b.status = Status.Approved;
            _executeBallot(ballotIds);
        }
        
    
    }
    
    /**
     * @dev Apply changes from ballot.
     * @param ballotId The ballot index
     */
    function _executeBallot(uint256 ballotId) internal {
        require(ballots[ballotId].status == Status.Approved,"Ballot is not Approved");
        Ballot storage b = ballots[ballotId];
        Rule storage r = rules[b.ruleId];
        bytes memory command = abi.encodePacked(bytes4(keccak256(bytes(r.funcAbi))), b.args);
        trigger(r.contr, command);
        b.closeVote = block.timestamp;
        emit ApplyBallot(b.ruleId, ballotId);
    }


    /**
     * @dev Apply changes from Governance System. Call destination contract.
     * @param contr The contract address to call
     * @param params encoded params
     */
    function trigger(address contr, bytes memory params) internal  {
        contr.call(params);
    }
    
    function acceptOwnership(address which) public {
        Ownable(which).acceptOwnership();
    }
    
}
