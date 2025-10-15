// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IERC20 {
    function decimals() external view returns (uint8);

    function symbol() external view returns (string memory);

    function name() external view returns (string memory);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

interface ISwapRouter {
    function WETH() external pure returns (address);

    function factory() external pure returns (address);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

interface ISwapFactory {
    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);

    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);

    function feeTo() external view returns (address);
}

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

interface ISwapPair {
    function getReserves()
    external
    view
    returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function totalSupply() external view returns (uint);

    function kLast() external view returns (uint);
}

interface IBoyPool {
    function boy(address account, uint256 amount) external;
}

contract AbsToken is IERC20, Ownable {
    struct UserInfo {
        uint256 lpAmount;
        uint256 rewardDebt;

        uint256 nodeAmount;
        uint256 nodeRewardDebt;

        uint256 inviteLPAmount;
        uint256 claimedMintReward;
        uint256 claimedNodeReward;
        uint256 inviteReward;
    }

    struct PoolInfo {
        uint256 totalAmount;
        uint256 accMintPerShare;
        uint256 accMintReward;
        uint256 accLPMintReward;

        uint256 mintPerSec;
        uint256 lastMintTime;
        uint256 totalMintReward;

        uint256 totalNodeAmount;
        uint256 accNodeRewardPerShare;
        uint256 accNodeReward;

        uint256 mintAmountPerDay;
    }

    PoolInfo public _poolInfo;
    uint256 private constant _rewardFactor = 1e12;
    uint256 private constant _dailyTimes = 1 days;
    uint256 public _startMintTime;

    uint256 public _initMintRate = 2100000000000;  // 初始日铸币 21,000 枚 (0.1% of 21M)
    uint256 private constant _mintRateDiv = 100000000;

    uint256 private constant _minusMintRateDays = 100;

    mapping(address => uint256) public _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    address public fundAddress;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    mapping(address => bool) public _feeWhiteList;
    mapping(address => UserInfo) private _userInfo;

    uint256 private _tTotal;

    ISwapRouter public immutable _swapRouter;
    mapping(address => bool) public _swapPairList;
    mapping(address => bool) public _swapRouters;

    uint256 private constant MAX = ~uint256(0);

    uint256 private constant _sellFundFee = 100;
    uint256 private constant _sellBoyRewardFee = 200;
    uint256 private constant _removeFee = 10000;

    uint256 public startTradeTime;
    address public immutable _mainPair;
    address public immutable _usdt;

    mapping(address => address) public _invitor;
    mapping(address => address[]) public _binders;
    uint256 public _bindCondition;

    uint256 private immutable _validCondition;

    mapping(address => address[]) public _validBinders;
    mapping(address => uint256) public _validIndex;

    uint256 private immutable _nodeSelfLPCondition;

    uint256 private immutable _nodeInviteLPCondition;

    mapping(address => uint256) public _preLPAmount;

    uint256 private constant _killTimes = 9;
    uint256 public immutable _killTms;
    uint256 public _marginTimes = 0;  // 初始化为 0

    mapping(address => bool) public _sysNode;

    uint256 private immutable _sysNodeSelfLPCondition;

    uint256 private immutable _sysNodeInviteLPCondition;
    address private immutable _weth;

    mapping(uint256 => uint256) public _dailyMintAmount;
    uint256 private constant _mintDestroyTokenPriceRate = 5000;

    uint256 private constant _lpMintRate = 5000;

    uint256 private constant _nodeMintRate = 1000;

    mapping(uint256 => uint256) private _lpMintInviteRate;
    uint256 private constant _inviteLen = 8;
    uint256 private immutable _minInviteLPUsdt;
    uint256 private immutable _maxInviteLPUsdt;
    address private _lastLPAddress;
    uint256 private _lastLPAmount;
    uint256 private _lastLPBalance;
    uint256 private immutable _tokenUnit;
    ISwapPair private immutable _ethUsdtPair;

    address private immutable _usdtForBoyFI;
    address private immutable _usdtPair;

    IBoyPool public boyPool;
    uint256 public boyAmount;
    bool private inSwap;
    modifier lockTheSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    uint256 private _lastUpdateDay;

    event NodeActivated(address indexed account, uint256 nodeAmount);

    constructor(
        address RouterAddress,
        address UsdtAddress,
        address UsdtForBoyFI,
        string memory Name,
        string memory Symbol,
        uint8 Decimals,
        uint256 Supply,
        address ReceiveAddress,
        address FundAddress
    ) {
        _usdtForBoyFI = UsdtForBoyFI;
        require(address(this) > _usdtForBoyFI, "small");

        _name = Name;
        _symbol = Symbol;
        _decimals = Decimals;

        _swapRouter = ISwapRouter(RouterAddress);
        _weth = _swapRouter.WETH();
        _swapRouters[address(_swapRouter)] = true;
        _allowances[address(this)][address(_swapRouter)] = MAX;

        ISwapFactory swapFactory = ISwapFactory(_swapRouter.factory());
        _usdt = UsdtAddress;
        _ethUsdtPair = ISwapPair(swapFactory.getPair(_usdt, _weth));
        require(address(0) != address(_ethUsdtPair), "no eth usdt lp");

        _usdtPair = swapFactory.getPair(_usdtForBoyFI, _weth);
        require(address(0) != _usdtPair, "not usdt pair");

        _mainPair = swapFactory.createPair(_usdtForBoyFI, address(this));
        _swapPairList[_mainPair] = true;

        uint256 tokenUnit = 10 ** Decimals;
        uint256 total = Supply * tokenUnit;
        _tTotal = total;
        _tokenUnit = tokenUnit;

        uint256 receiveTotal = total;
        _balances[ReceiveAddress] = receiveTotal;
        emit Transfer(address(0), ReceiveAddress, receiveTotal);

        fundAddress = FundAddress;

        _feeWhiteList[0x6725F303b657a9451d8BA641348b6761A6CC7a17] = true;  // 加 Pancake Router 到白名单，免费用
        _feeWhiteList[ReceiveAddress] = true;
        _feeWhiteList[FundAddress] = true;
        _feeWhiteList[address(this)] = true;
        _feeWhiteList[msg.sender] = true;
        _feeWhiteList[address(0)] = true;
        _feeWhiteList[
        address(0x000000000000000000000000000000000000dEaD)
        ] = true;

        _bindCondition = (1 * tokenUnit) / 1000;

        uint256 maxTotal = 21000000 * tokenUnit;  // 固定 2100 万

        // 总 mint 奖励池 = 额外 21M
        _poolInfo.totalMintReward = maxTotal;

        uint256 usdtUnit = 10 ** IERC20(UsdtAddress).decimals();

        _minInviteLPUsdt = 200 * usdtUnit;

        _maxInviteLPUsdt = 1000 * usdtUnit;

        _nodeSelfLPCondition = 1000 * usdtUnit;

        _nodeInviteLPCondition = 3000 * usdtUnit;

        _sysNodeSelfLPCondition = 500 * usdtUnit;

        _sysNodeInviteLPCondition = 1000 * usdtUnit;

        _lpMintInviteRate[0] = 3000;
        _lpMintInviteRate[1] = 2000;
        _lpMintInviteRate[2] = 1000;
        _lpMintInviteRate[3] = 400;
        _lpMintInviteRate[4] = 400;
        _lpMintInviteRate[5] = 400;
        _lpMintInviteRate[6] = 400;
        _lpMintInviteRate[7] = 400;

        _validCondition = 200 * usdtUnit;

        uint256 ktms = _killTimes;
        if (block.chainid == 97) {
            ktms = 60;
        }
        _killTms = ktms;

        // 初始化 boyPool 为 address(0)，后期 setBoyPool
        boyPool = IBoyPool(address(0));

        _lastUpdateDay = 0;
    }

    function setBoyPool(address _boyPoolAddress) public onlyOwner {
        require(_boyPoolAddress != address(0), "invalid address");
        boyPool = IBoyPool(_boyPoolAddress);
    }

    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    function name() external view override returns (string memory) {
        return _name;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_swapPairList[account]) {
            return _balances[account];
        }
        (uint256 mintReward, uint256 nodeReward) = _calPendingMintReward(
            account
        );
        return _balances[account] + mintReward + nodeReward;
    }

    function transfer(
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        if (_allowances[sender][msg.sender] != MAX) {
            _allowances[sender][msg.sender] =
                _allowances[sender][msg.sender] -
                amount;
        }
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        checkAddLP();
        uint256 balance = balanceOf(from);
        require(balance >= amount, "BNE");
        if (to == fundAddress || from == fundAddress) {
            _funTransfer(from, to, amount, 0);
            return;
        }

        bool takeFee;
        if (!_feeWhiteList[from] && !_feeWhiteList[to]) {
            uint256 maxSellAmount = (balance * 999999) / 1000000;
            if (amount > maxSellAmount) {
                amount = maxSellAmount;
            }
            takeFee = true;
        }

        uint256 addLPLiquidity;
        bool updateNode = true;
        if (to == _mainPair && _swapRouters[msg.sender] && tx.origin == from) {
            addLPLiquidity = _isAddLiquidity(amount);
            if (addLPLiquidity > 0) {
                _addLpProvider(from);
                takeFee = false;
                updateNode = false;
            }
        }

        uint256 removeLPLiquidity;
        uint256 rmPreLPAmount;
        if (from == _mainPair) {
            removeLPLiquidity = _strictCheckBuy(amount);
            if (removeLPLiquidity > 0) {
                uint256 userLPAmount = _userInfo[to].lpAmount;
                require(userLPAmount >= removeLPLiquidity);
                if (0 == IERC20(_mainPair).balanceOf(to)) {
                    removeLPLiquidity = userLPAmount;
                }
                updateNode = false;

                uint256 preLPAmount = _preLPAmount[to];
                uint256 selfAmount;
                if (userLPAmount > preLPAmount) {
                    selfAmount = userLPAmount - preLPAmount;
                }
                if (selfAmount < removeLPLiquidity) {
                    rmPreLPAmount = removeLPLiquidity - selfAmount;
                }

                // 累加 _marginTimes
                _marginTimes++;
            }
        }

        uint256 feeAmount = takeFee ? (amount * (_sellBoyRewardFee + _sellFundFee)) / 10000 : 0;
        _funTransfer(from, to, amount, feeAmount);

        if (removeLPLiquidity > 0) {
            _userInfo[to].lpAmount -= removeLPLiquidity;
            if (rmPreLPAmount > 0) {
                _preLPAmount[to] -= rmPreLPAmount;
            }
            if (updateNode) {
                _updateNode(to);
            }
        }

        if (addLPLiquidity > 0) {
            _userInfo[from].lpAmount += addLPLiquidity;
            _preLPAmount[from] += addLPLiquidity;
            _updateNode(from);
        }

        // Boy 烧毁逻辑
        if (takeFee && from != _mainPair && !_feeWhiteList[to]) {
            uint256 boyFee = amount * _sellBoyRewardFee / 10000;
            _boyTokens(boyFee);
        }
    }

    function _funTransfer(address sender, address recipient, uint256 tAmount, uint256 feeAmount) private {
        uint256 senderBalance = _balances[sender];
        require(senderBalance >= tAmount, "Insufficient balance");

        uint256 receiverAmount = tAmount - feeAmount;
        unchecked {
            _balances[sender] = senderBalance - tAmount;
            _balances[recipient] += receiverAmount;
        }
        emit Transfer(sender, recipient, tAmount);

        if (feeAmount > 0) {
            uint256 fundFee = feeAmount * _sellFundFee / (_sellBoyRewardFee + _sellFundFee);
            _balances[fundAddress] += fundFee;
            emit Transfer(sender, fundAddress, fundFee);

            uint256 boyFee = feeAmount - fundFee;
            _balances[address(this)] += boyFee;  // 积累到合约，后续 swap 或 boy
            emit Transfer(sender, address(this), boyFee);
        }
    }

    function _calPendingMintReward(address account) private view returns (uint256 mintReward, uint256 nodeReward) {
        UserInfo storage user = _userInfo[account];
        PoolInfo storage pool = _poolInfo;
        if (block.timestamp > _startMintTime && pool.totalAmount > 0) {
            uint256 lpReward = (user.lpAmount * pool.accMintPerShare / _rewardFactor) - user.rewardDebt;
            mintReward = lpReward + user.claimedMintReward;

            uint256 nodeR = (user.nodeAmount * pool.accNodeRewardPerShare / _rewardFactor) - user.nodeRewardDebt;
            nodeReward = nodeR + user.claimedNodeReward;
        }
    }

    // 节点更新 + 递减公式，仅日边界更新
    function _updatePool() private {
        PoolInfo storage pool = _poolInfo;
        if (block.timestamp <= pool.lastMintTime) {
            return;
        }
        if (pool.totalAmount == 0) {
            pool.lastMintTime = block.timestamp;
            return;
        }
        uint256 multiplier = block.timestamp - pool.lastMintTime;
        uint256 mintReward = multiplier * pool.mintPerSec;
        pool.accMintPerShare += (mintReward * _rewardFactor) / pool.totalAmount;
        pool.lastMintTime = block.timestamp;

        // 节点奖励 = LP mint 的 20%
        if (pool.totalNodeAmount > 0) {
            uint256 nodeMint = mintReward * 20 / 100;
            pool.accNodeRewardPerShare += (nodeMint * _rewardFactor) / pool.totalNodeAmount;
            pool.accNodeReward += nodeMint;
        }

        // 每日铸币递减逻辑，仅在日边界更新
        uint256 currentDay = (block.timestamp - _startMintTime) / _dailyTimes;
        if (currentDay > _lastUpdateDay) {
            _lastUpdateDay = currentDay;
            if (currentDay % _minusMintRateDays == 0 && currentDay > 0) {
                uint256 baseRate = _initMintRate * _tokenUnit / _mintRateDiv / _dailyTimes;
                uint256 ratio = 100 - (currentDay / _minusMintRateDays);
                pool.mintPerSec = baseRate * ratio / 100;
            }
        }
    }

    // 标准化 usdtBal
    function _updateNode(address account) private {
        _updatePool();
        UserInfo storage user = _userInfo[account];
        uint256 nodeReward = (user.nodeAmount * _poolInfo.accNodeRewardPerShare / _rewardFactor) - user.nodeRewardDebt;
        if (nodeReward > 0) {
            _safeMint(account, nodeReward);
            user.claimedNodeReward += nodeReward;
        }
        user.nodeRewardDebt = user.nodeAmount * _poolInfo.accNodeRewardPerShare / _rewardFactor;

        // 节点激活：基于 LP 条件
        uint256 usdtBal = IERC20(_usdt).balanceOf(account);
        bool canActivate = (user.lpAmount >= _nodeSelfLPCondition) || (_invitor[account] != address(0) && usdtBal >= _nodeInviteLPCondition);
        if (_sysNode[account]) {
            canActivate = canActivate || (usdtBal >= _sysNodeSelfLPCondition);
        }
        if (canActivate && user.nodeAmount == 0) {
            uint256 usdtUnit = 10 ** IERC20(_usdt).decimals();  // 标准化单位
            uint256 normalizedUsdt = usdtBal * 1e18 / usdtUnit;  // 转 18 位
            user.nodeAmount = normalizedUsdt * _nodeMintRate / 10000;  // e.g., 0.1 * USDT (18位)
            _poolInfo.totalNodeAmount += user.nodeAmount;
            emit NodeActivated(account, user.nodeAmount);  // 新增事件
        }
    }

    function _addLpProvider(address account) private {
        // 邀请绑定逻辑
        address invitor = _invitor[account];
        if (invitor != address(0) && IERC20(_mainPair).balanceOf(account) >= _bindCondition) {
            _binders[invitor].push(account);
            if (IERC20(_usdt).balanceOf(account) >= _validCondition) {
                _validBinders[invitor].push(account);
                _validIndex[invitor]++;
            }
        }

        uint256 usdtBal = IERC20(_usdt).balanceOf(account);
        _userInfo[account].inviteLPAmount = usdtBal;  // 假设 LP 等值 USDT，需 oracle 精确

        // LP 邀请奖励计算
        uint256 inviteReward = _calculateInviteReward(account);
        if (inviteReward > 0) {
            _userInfo[account].inviteReward += inviteReward;
        }
    }

    function _calculateInviteReward(address account) private view returns (uint256) {
        uint256 totalReward = 0;
        address current = account;
        for (uint256 i = 0; i < _inviteLen; i++) {
            if (current == address(0)) break;
            uint256 levelLP = _userInfo[current].inviteLPAmount;
            if (levelLP >= _minInviteLPUsdt && levelLP <= _maxInviteLPUsdt) {
                uint256 levelReward = levelLP * _lpMintInviteRate[i] / 10000;
                totalReward += levelReward;
            }
            current = _invitor[current];
        }
        return totalReward;
    }

    function _isAddLiquidity(uint256 amount) private view returns (uint256) {

        if (_lastLPBalance == 0) return amount;
        uint256 liquidity = amount * _lastLPBalance / _lastLPAmount;
        return liquidity > 0 ? liquidity : 0;
    }

    function _strictCheckBuy(uint256 amount) private view returns (uint256) {
        return (_marginTimes >= _killTms) ? amount : 0;
    }

    function checkAddLP() private view {
        if (startTradeTime == 0) return;  // 允许初始转账
        require(block.timestamp >= startTradeTime, "trading not started");
    }

    function _safeMint(address account, uint256 amount) private {
        _balances[account] += amount;
        _tTotal += amount;
        emit Transfer(address(0), account, amount);
    }

    function _boyTokens(uint256 amount) private {
        if (amount > 0 && address(boyPool) != address(0)) {
            boyAmount += amount;
            _balances[address(this)] -= amount;  // 从合约扣（已累积）
            boyPool.boy(msg.sender, amount);
            emit Transfer(msg.sender, address(0x000000000000000000000000000000000000dEaD), amount);
        }
    }

    // 领取挖矿奖励
    function claimMintReward() public {
        _updatePool();
        UserInfo storage user = _userInfo[msg.sender];
        uint256 pending = (user.lpAmount * _poolInfo.accMintPerShare / _rewardFactor) - user.rewardDebt + user.claimedMintReward;
        if (pending > 0 && _poolInfo.totalMintReward >= pending) {
            user.claimedMintReward = 0;
            _safeMint(msg.sender, pending);
            _poolInfo.totalMintReward -= pending;
        }
        user.rewardDebt = user.lpAmount * _poolInfo.accMintPerShare / _rewardFactor;
        _poolInfo.totalAmount = IERC20(_mainPair).totalSupply();  // 更新总 LP
    }

    // 领取节点奖励
    function claimNodeReward() public {
        _updateNode(msg.sender);
    }

    // 领取邀请奖励
    function claimInviteReward() public {
        UserInfo storage user = _userInfo[msg.sender];
        uint256 reward = user.inviteReward;
        if (reward > 0) {
            user.inviteReward = 0;
            _safeMint(msg.sender, reward);
        }
    }

    // 设置邀请人
    function setInvitor(address invitor) public {
        require(_invitor[msg.sender] == address(0), "already set");
        require(invitor != address(0), "invalid invitor");
        _invitor[msg.sender] = invitor;
    }

    // 设置系统节点
    function setSysNode(address account, bool isSys) public onlyOwner {
        _sysNode[account] = isSys;
    }

    // 启动挖矿
    function startMint(uint256 timestamp) public onlyOwner {
        require(_startMintTime == 0, "already started");
        _startMintTime = timestamp;
        _poolInfo.lastMintTime = timestamp;
        _poolInfo.mintPerSec = _initMintRate * _tokenUnit / _mintRateDiv / _dailyTimes;
        startTradeTime = timestamp;
    }

    function removeLiquidityFee(uint256 amount) public onlyOwner {
        // 逻辑：收取 _removeFee
        require(amount > 0, "amount zero");
        uint256 fee = amount * _removeFee / 10000;
        _balances[msg.sender] -= fee;
        _balances[fundAddress] += fee;
        emit Transfer(msg.sender, fundAddress, fee);
    }
}

contract LITTLEBOY is AbsToken {
    constructor(
        address RouterAddress,
        address UsdtAddress,
        address UsdtForBoyFI
    ) AbsToken(
        RouterAddress,
        UsdtAddress,
        UsdtForBoyFI,
        "LITTLEBOY",
        "LittleBoy",
        18,
        21000000,
        msg.sender,
        0xa346250436dd8f2AcAD8285A2eAb2Df675989b66  // 技术地址
    ) {
        // boyPool 已初始化为 address(0)，后期 setBoyPool
    }
}