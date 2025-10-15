// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract Ownable {
    address internal _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        address msgSender = msg.sender;
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "!o");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "n0");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract AbsPool is Ownable {

    mapping(address => uint256) public totalBoyAmount;
    mapping(address => uint256) public pendingBNBReward;
    mapping(address => uint256) public claimedBNBReward;


    struct BoyRecord {
        address account;
        uint256 boyAmount; 
    }
    BoyRecord[] public boyRecord;

    uint256 public rewardRate = 13000;  // 1.3% (预估率，可用于 oracle 调整)
    address private immutable _token;  // LITTLEBOY 地址
    address public fund;
    uint256 public rewardLen = 5;
    uint256 public headIndex;
    uint256 public totalBoy;  // 总 boy token
    uint256 public totalPayReward;  // 总支付 BNB

    bool private inSwap;
    modifier lockTheSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor(address Token) {
        _token = Token;
        // 初始化 fund 为技术地址
        fund = 0xa346250436dd8f2AcAD8285A2eAb2Df675989b66;
    }

    function _addReward(uint256 bnbReward) private lockTheSwap {
        if (bnbReward == 0 || totalBoy == 0) return;

        // 简化：全 pro-rata 基于 totalBoyAmount (假设维护活跃烧毁者总和)
        // 注意：为精确，需维护活跃总 boy 或用数组限 len
        // 这里用最近 rewardLen 条记录作为近似
        uint256 start = headIndex;
        uint256 end = start + rewardLen;
        uint256 recordLen = boyRecord.length;
        if (end > recordLen) end = recordLen;
        if (start >= end) return;

        uint256 totalBoyAmountInWindow;
        for (uint256 i = start; i < end; ++i) {
            totalBoyAmountInWindow += boyRecord[i].boyAmount;
        }
        if (totalBoyAmountInWindow == 0) return;

        // 按比例累积 pending BNB
        for (uint256 i = start; i < end; ++i) {
            address acc = boyRecord[i].account;
            uint256 share = (bnbReward * boyRecord[i].boyAmount) / totalBoyAmountInWindow;
            pendingBNBReward[acc] += share;
        }

        // 滑动窗口：检查可 claim（假设按序）
        uint256 payIndex = start;
        for (uint256 i = start; i < end; ++i) {
            address acc = boyRecord[i].account;
            uint256 pending = pendingBNBReward[acc] - claimedBNBReward[acc];
            if (pending > 0) {
                // 全额发送 pending BNB
                _safeTransferBNB(acc, pending);
                claimedBNBReward[acc] += pending;
                totalPayReward += pending;
                payIndex++;
            } else {
                break;
            }
        }
        headIndex = payIndex;
    }

    // 发送 BNB
    function _safeTransferBNB(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "BNB transfer failed");
    }

    receive() external payable {
        if (!inSwap) {
            _addReward(msg.value);  // msg.value 是 BNB
        }
    }

    // 记录实际 boy amount，用 mapping
    function boy(address account, uint256 boyAmount) external {
        require(boyAmount > 0, "not 0");
        require(msg.sender == _token, "only token");  // 只允许 LITTLEBOY 调用
        totalBoy += boyAmount;
        totalBoyAmount[account] += boyAmount;
        // 保留记录到数组（历史）
        boyRecord.push(BoyRecord(account, boyAmount));
    }

    // 手动 claim BNB 奖励，用 mapping
    function claimBNBReward() external {
        uint256 pending = pendingBNBReward[msg.sender] - claimedBNBReward[msg.sender];
        if (pending > 0) {
            claimedBNBReward[msg.sender] += pending;
            totalPayReward += pending;
            _safeTransferBNB(msg.sender, pending);
            pendingBNBReward[msg.sender] = 0;  // 重置
        }
    }

    function claimBalance(address to, uint256 amount) external onlyOF {
        _safeTransferBNB(to, amount);
    }

    // setFund 改 onlyOwner
    function setFund(address f) external onlyOwner {
        fund = f;
    }

    function claimToken(
        address token,
        address to,
        uint256 amount
    ) external onlyOF {
        _safeTransfer(token, to, amount);
    }

    modifier onlyOF() {
        address msgSender = msg.sender;
        require((msgSender == fund || msgSender == _owner), "of");
        _;
    }

    function _safeTransfer(address token, address to, uint value) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0xa9059cbb, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TF"
        );
    }

    function setRewardRate(uint256 rate) public onlyOwner {
        rewardRate = rate;
    }

    function setRewardLen(uint256 len) public onlyOwner {
        rewardLen = len;
    }

    function getBoyLen() public view returns (uint256 len) {  
        len = boyRecord.length;
    }
}

contract BoyPool is AbsPool {  // 别名 BoyFI
    constructor(address LittleBoyToken) AbsPool(LittleBoyToken) {}  // 关联 LITTLEBOY
}