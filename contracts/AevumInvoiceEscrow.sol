// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}

/**
 * @title AevumInvoiceEscrow
 * @notice Trustless stablecoin (tUSD8 / ERC-20) Invoice Payment & Confirmation-of-Payee
 *         Escrow built for QDay Aevum Testnet (Chain ID 44005).
 */
contract AevumInvoiceEscrow {
    enum InvoiceStatus {
        Open,
        Escrowed,
        Paid,
        Refunded,
        Cancelled
    }

    struct Invoice {
        uint256 id;
        address issuer;
        address expectedPayer; // address(0) = open to any payer
        address token;         // tUSD8 or compatible ERC-20 stablecoin
        uint256 amount;
        uint64 dueAt;
        bool useEscrow;        // false = instant settle; true = milestone escrow
        bytes32 payeeNameHash; // Confirmation of Payee (keccak256 of legal/studio name)
        string referenceCode;  // e.g. "INV-2026-001"
        string metadataURI;    // optional IPFS / JSON summary hash
        InvoiceStatus status;
        address paidBy;
        uint64 settledAt;
    }

    uint256 public nextInvoiceId = 1;
    mapping(uint256 => Invoice) public invoices;
    mapping(address => uint256[]) private _issuerInvoices;
    mapping(address => uint256[]) private _payerInvoices;

    uint256 private _locked = 1;
    modifier nonReentrant() {
        require(_locked == 1, "REENTRANCY");
        _locked = 2;
        _;
        _locked = 1;
    }

    event InvoiceCreated(
        uint256 indexed id,
        address indexed issuer,
        address indexed token,
        uint256 amount,
        bool useEscrow,
        bytes32 payeeNameHash,
        string referenceCode
    );
    event InvoicePaid(uint256 indexed id, address indexed payer, uint256 amount, bool escrowed);
    event InvoiceReleased(uint256 indexed id, address indexed issuer, uint256 amount);
    event InvoiceRefunded(uint256 indexed id, address indexed payer, uint256 amount);
    event InvoiceCancelled(uint256 indexed id, address indexed issuer);

    function createInvoice(
        address token,
        uint256 amount,
        address expectedPayer,
        uint64 dueAt,
        bool useEscrow,
        bytes32 payeeNameHash,
        string calldata referenceCode,
        string calldata metadataURI
    ) external returns (uint256 id) {
        require(token != address(0), "INVALID_TOKEN");
        require(amount > 0, "INVALID_AMOUNT");
        require(bytes(referenceCode).length > 0, "EMPTY_REF");

        id = nextInvoiceId++;
        invoices[id] = Invoice({
            id: id,
            issuer: msg.sender,
            expectedPayer: expectedPayer,
            token: token,
            amount: amount,
            dueAt: dueAt,
            useEscrow: useEscrow,
            payeeNameHash: payeeNameHash,
            referenceCode: referenceCode,
            metadataURI: metadataURI,
            status: InvoiceStatus.Open,
            paidBy: address(0),
            settledAt: 0
        });
        _issuerInvoices[msg.sender].push(id);
        emit InvoiceCreated(id, msg.sender, token, amount, useEscrow, payeeNameHash, referenceCode);
    }

    /**
     * @notice Pay an open invoice with Confirmation-of-Payee verification.
     * @param id Invoice ID.
     * @param confirmedPayeeNameHash Must match invoice.payeeNameHash to prevent wrong-recipient errors.
     */
    function payInvoice(uint256 id, bytes32 confirmedPayeeNameHash) external nonReentrant {
        Invoice storage inv = invoices[id];
        require(inv.id != 0, "NOT_FOUND");
        require(inv.status == InvoiceStatus.Open, "NOT_OPEN");
        if (inv.expectedPayer != address(0)) {
            require(msg.sender == inv.expectedPayer, "WRONG_PAYER");
        }
        require(inv.payeeNameHash == confirmedPayeeNameHash, "PAYEE_MISMATCH");

        inv.paidBy = msg.sender;
        _payerInvoices[msg.sender].push(id);

        if (inv.useEscrow) {
            inv.status = InvoiceStatus.Escrowed;
            require(IERC20(inv.token).transferFrom(msg.sender, address(this), inv.amount), "TRANSFER_FAILED");
            emit InvoicePaid(id, msg.sender, inv.amount, true);
        } else {
            inv.status = InvoiceStatus.Paid;
            inv.settledAt = uint64(block.timestamp);
            require(IERC20(inv.token).transferFrom(msg.sender, inv.issuer, inv.amount), "TRANSFER_FAILED");
            emit InvoicePaid(id, msg.sender, inv.amount, false);
        }
    }

    /**
     * @notice Payer approves deliverable and releases escrowed funds to the invoice issuer.
     */
    function releaseEscrow(uint256 id) external nonReentrant {
        Invoice storage inv = invoices[id];
        require(inv.status == InvoiceStatus.Escrowed, "NOT_ESCROWED");
        require(msg.sender == inv.paidBy, "ONLY_PAYER");

        inv.status = InvoiceStatus.Paid;
        inv.settledAt = uint64(block.timestamp);
        require(IERC20(inv.token).transfer(inv.issuer, inv.amount), "RELEASE_FAILED");
        emit InvoiceReleased(id, inv.issuer, inv.amount);
    }

    /**
     * @notice Issuer voluntarily refunds an escrowed invoice back to the payer.
     */
    function refundEscrow(uint256 id) external nonReentrant {
        Invoice storage inv = invoices[id];
        require(inv.status == InvoiceStatus.Escrowed, "NOT_ESCROWED");
        require(msg.sender == inv.issuer, "ONLY_ISSUER");

        inv.status = InvoiceStatus.Refunded;
        inv.settledAt = uint64(block.timestamp);
        require(IERC20(inv.token).transfer(inv.paidBy, inv.amount), "REFUND_FAILED");
        emit InvoiceRefunded(id, inv.paidBy, inv.amount);
    }

    function cancelInvoice(uint256 id) external {
        Invoice storage inv = invoices[id];
        require(inv.status == InvoiceStatus.Open, "NOT_OPEN");
        require(msg.sender == inv.issuer, "ONLY_ISSUER");
        inv.status = InvoiceStatus.Cancelled;
        emit InvoiceCancelled(id, msg.sender);
    }

    function getIssuerInvoices(address issuer) external view returns (uint256[] memory) {
        return _issuerInvoices[issuer];
    }

    function getPayerInvoices(address payer) external view returns (uint256[] memory) {
        return _payerInvoices[payer];
    }
}
