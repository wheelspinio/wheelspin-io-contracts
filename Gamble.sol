/* @author https://github.com/bertolo1988 */
pragma solidity ^0.5.10;

import './oraclizeAPI_0.5.sol';
import './Ownable.sol';
import './SafeMath.sol';

contract Gamble is Ownable, usingOraclize {

    using SafeMath for uint;

    uint public constant MIN_DEPOSIT = 0.1 ether;
    uint public constant MAX_ROLL_UNDER = 96;
    uint public constant MIN_ROLL_UNDER = 6;
    uint constant MAX_INT_FROM_BYTE = 256;
    uint constant NUM_RANDOM_BYTES_REQUESTED = 7;

    uint public minBet = 0.05 ether;
    uint public maxBet = 1 ether;
    uint private nonce;
    uint public houseCommissionPercentage = 3;

    struct Bet {
        uint spinUnder;
        uint stake;
        uint prize;
        uint payout;
        address sender;
    }

    mapping (bytes32 => Bet) private ongoingBets;
    mapping (address => uint) private balances;

    event logDeposit(address indexed _from, uint _value, uint _newBalance);
    event logWithdraw(address indexed _from, uint _value, uint _newBalance);
    event logBetStarted(address indexed _from, uint _spinUnder, uint _stake, uint _prize, uint _payout, uint _previousBalance);
    event logBetSuccess(address indexed _from, uint _spin, uint _spinUnder, uint _stake, uint _prize, uint _payout, uint _newBalance);

    constructor() public {
        oraclize_setProof(proofType_Ledger);
    }

    // sets max bet value
    function setMaxBet(uint _maxBet) external onlyOwner{
        require(_maxBet > minBet, 'maxBet must be bigger than minBet');
        maxBet = _maxBet;
    }

    // sets max bet value
    function setMinBet(uint _minBet) external onlyOwner{
        require(_minBet > 0 && _minBet < maxBet, 'minBet must be between 0 and maxBet');
        minBet = _minBet;
    }

    // sets the house commission percentage
    function setHouseCommissionPercentage(uint _houseCommissionPercentage) external onlyOwner{
        require(_houseCommissionPercentage > 0 && _houseCommissionPercentage < 100, 'houseCommissionPercentage must be between 0 and 100');
        houseCommissionPercentage = _houseCommissionPercentage;
    }

    // player get expected payout for a given play
    function calculatePayoutMultiplierTimesHundred(uint probability) private view returns(uint){
        require(probability < 100 && probability > 0, 'probability must be between 0 and 100');
        uint breakEven = (100*(100 - probability)) / probability + 100;
        return breakEven*(100-houseCommissionPercentage)/100;
    }

    // moves ether from user to owner
    function subtractAmountFromUser(uint amount) private {
        balances[msg.sender] =  balances[msg.sender].sub(amount);
        balances[owner] = balances[owner].add(amount);
    }

    // moves ether from owner to user
    function addAmountToUser(address _user, uint amount) private {
        balances[owner] = balances[owner].sub(amount);
        balances[_user] =  balances[_user].add(amount);
    }

    // withdraws ether in a user balance
    function withdraw(uint amount) external returns (uint){
        require(amount <= balances[msg.sender], 'insufficient balance');
        balances[msg.sender] = balances[msg.sender].sub(amount);
        msg.sender.transfer(amount);
        emit logWithdraw(msg.sender, amount, balances[msg.sender]);
        return balances[msg.sender];
    }

    // deposits ether in a user balance
    function deposit() external payable returns (uint){
        require(msg.value >= MIN_DEPOSIT, 'below minimum deposit');
        balances[msg.sender] = balances[msg.sender].add(msg.value);
        emit logDeposit(msg.sender, msg.value, balances[msg.sender]);
        return balances[msg.sender];
    }

    // gets sender balance
    function getBalance() view external returns (uint) {
        return balances[msg.sender];
    }

    // gets address balance
    function getBalanceByAddress(address walletAddress) view external returns (uint) {
        return balances[walletAddress];
    }

    // gets owner balance
    function ownerBalance() view external returns (uint) {
        return balances[owner];
    }

    // calculates the prize and payout for a given bet
    function getPrizeAndPayout(uint stake, uint spinUnder) public view returns (uint payout, uint prize){
        payout = calculatePayoutMultiplierTimesHundred(spinUnder-1);
        prize = stake.mul(payout) / 100;
        return (payout, prize);
    }

    function __callback( bytes32 _queryId, string memory _result, bytes memory _proof ) public {
        require(msg.sender == oraclize_cbAddress());
        require(ongoingBets[_queryId].sender != address(0x0) , 'query does not exist');
        if(oraclize_randomDS_proofVerify__returnCode( _queryId, _result, _proof) != 0){
            revert();
        } else {
            uint ceiling = (MAX_INT_FROM_BYTE ** NUM_RANDOM_BYTES_REQUESTED) - 1;
            uint randomNumber = uint(keccak256(abi.encodePacked(_result))) % ceiling;
            uint spin = (randomNumber % 100) + 1;
            Bet memory bet = ongoingBets[_queryId];
            if(spin < bet.spinUnder){
                addAmountToUser(bet.sender, bet.prize);
            }
            emit logBetSuccess(bet.sender, spin, bet.spinUnder, bet.stake, bet.prize, bet.payout, balances[bet.sender]);
            delete ongoingBets[_queryId];
        }
    }

    function bet(uint stake, uint spinUnder)external notOwner returns (uint spinUnderInput, uint stakeInput, uint prize, uint payout, uint previousBalance){
        require(stake >= minBet , 'stake is too small');
        require(maxBet >= stake, 'stake is too big');
        require(spinUnder >= MIN_ROLL_UNDER && spinUnder <= MAX_ROLL_UNDER, 'spinUnder must be between or equal to 11 and 91');
        require(balances[msg.sender] >= stake, 'insufficient balance to cover stake');
        (payout, prize) = getPrizeAndPayout(stake, spinUnder);
        require(balances[owner] >=  (prize.sub(stake)), 'insufficient contract balance to cover the prize');
        previousBalance = balances[msg.sender];
        subtractAmountFromUser(stake);
        uint QUERY_EXECUTION_DELAY = 0;
        uint GAS_FOR_CALLBACK = 200000;
        bytes32 queryId = oraclize_newRandomDSQuery(
            QUERY_EXECUTION_DELAY,
            NUM_RANDOM_BYTES_REQUESTED,
            GAS_FOR_CALLBACK
        );
        ongoingBets[queryId] = Bet(spinUnder, stake, prize, payout, msg.sender);
        emit logBetStarted(msg.sender, spinUnder, stake, prize, payout, previousBalance);
        return (spinUnder, stake, prize, payout, previousBalance);
    }

}
