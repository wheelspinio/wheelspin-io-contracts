/* @author https://github.com/bertolo1988 */
pragma solidity ^0.5.10;

contract Ownable {
  address public owner;

  constructor() public {
    owner = msg.sender;
  }

  modifier onlyOwner() {
    require(msg.sender == owner, 'caller must be the owner');
    _;
  }

  modifier notOwner() {
    require(msg.sender != owner, 'caller must not be the owner');
    _;
  }

  function isOwner() public view returns(bool){
      return msg.sender == owner;
  }

  function transferOwnership(address newOwner) public onlyOwner {
    require(newOwner != address(0), 'new owner is the zero address');
    owner = newOwner;
  }

}