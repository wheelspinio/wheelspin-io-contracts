/* @author https://github.com/bertolo1988 */
pragma solidity ^0.5.10;

import './Ownable.sol';

contract Gamble is Ownable {

    uint public constant MIN_DEPOSIT = 0.1 ether;
    uint public constant MAX_ROLL_UNDER = 96;
    uint public constant MIN_ROLL_UNDER = 6;

    uint public minBet = 0.05 ether;
    uint public maxBet = 1 ether;
    uint private nonce;
    uint public houseCommissionPercentage = 3;

    mapping (address => uint) private balances;

    event logDeposit(address indexed _from, uint _value, uint _newBalance);
    event logWithdraw(address indexed _from, uint _value, uint _newBalance);
    event logBet(address indexed _from, uint _stakeInput, uint _spinUnderInput, uint _spin, uint _payout, uint _prize, uint _previousBalance, uint _newBalance);

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

    // generate random number between 1 and 100
    function random() private returns (uint) {
        uint randomnumber = uint(keccak256(abi.encodePacked(now, msg.sender, nonce))) % 100;
        randomnumber = randomnumber + 1;
        nonce++;
        return randomnumber;
    }

    // moves ether from user to owner
    function subtractAmountFromUser(uint amount) private {
        balances[msg.sender] -= amount;
        balances[owner] += amount;
    }

    // moves ether from owner to user
    function addAmountToUser(uint amount) private {
        balances[owner] -= amount;
        balances[msg.sender] += amount;
    }

    // withdraws ether in a user balance
    function withdraw(uint amount) external returns (uint){
        require(amount <= balances[msg.sender], 'insufficient balance');
        balances[msg.sender] -= amount;
        msg.sender.transfer(amount);
        emit logWithdraw(msg.sender, amount, balances[msg.sender]);
        return balances[msg.sender];
    }

    // deposits ether in a user balance
    function deposit() external payable returns (uint){
        require(msg.value >= MIN_DEPOSIT, 'below minimum deposit');
        balances[msg.sender] += msg.value;
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
        prize = stake * payout / 100;
        return (payout, prize);
    }

    // implement another random with oracles by contacting random.org
    function bet(uint stake, uint spinUnder)external notOwner returns (uint stakeInput, uint spinUnderInput, uint spin, uint payout, uint prize, uint previousBalance, uint newBalance){
        require(stake >= minBet , 'stake is too small');
        require(maxBet >= stake, 'stake is too big');
        require(spinUnder >= MIN_ROLL_UNDER && spinUnder <= MAX_ROLL_UNDER, 'spinUnder must be between or equal to 11 and 91');
        require(balances[msg.sender] >= stake, 'insufficient balance to cover stake');
        (payout, prize) = getPrizeAndPayout(stake, spinUnder);
        require(balances[owner] >=  (prize - stake), 'insufficient contract balance to cover the prize');
        previousBalance = balances[msg.sender];
        subtractAmountFromUser(stake);
        spin = random();
        if(spin < spinUnder){
            addAmountToUser(prize);
        }
        emit logBet(msg.sender,stake, spinUnder, spin, payout, prize, previousBalance, balances[msg.sender]);
        return (stake, spinUnder, spin, payout, prize, previousBalance, balances[msg.sender]);
    }

}
