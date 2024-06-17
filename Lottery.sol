// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./token/ERC20/IERC20.sol";
import "./access/Ownable.sol";

/**
 * @title DaxLotto
 * @dev The DaxLotto contract
 */
contract DaxLotto is Ownable, ReentrancyGuard {
    /// @notice The ERC20 token used for ticket payments
    IERC20 public token;

    /**
     * @dev Structure that contains the information of a lottery ticket.
     * @param id The unique ID of the ticket.
     * @param numbers The numbers chosen by the player.
     * @param timestamp The timestamp when the ticket was purchased.
     * @param pricePaid The actual price paid for the ticket, after any discounts.
     */
    struct Ticket {
        uint256 id;
        uint256[] numbers;
        uint256 timestamp;
        uint256 pricePaid;
    }

    /**
     * @dev Structure that contains the results of checking a ticket.
     * @param ticketId The unique ID of the checked ticket.
     * @param owner The address of the ticket owner.
     * @param correctNumbersCount The number of correctly guessed numbers.
     * @param correctNumbers A list of the correctly guessed numbers.
     */
    struct CheckResults {
        uint256 ticketId;
        address owner;
        uint256 correctNumbersCount;
        uint256[] correctNumbers;
    }

    /**
     * @dev Extended structure that contains additional information about a lottery ticket.
     * @param id The unique ID of the ticket.
     * @param numbers The numbers chosen by the player.
     * @param timestamp The timestamp when the ticket was purchased.
     * @param pricePaid The actual price paid for the ticket, after any discounts.
     * @param owner The address of the ticket owner.
     */
    struct ExtendedTicket {
        uint256 id;
        uint256[] numbers;
        uint256 timestamp;
        uint256 pricePaid;
        address owner;
    }

    /**
     * @dev Structure that contains the winning results of a ticket.
     * @param ticketId The unique ID of the ticket.
     * @param correctNumbersCount The number of correctly guessed numbers.
     */
    struct WinResult {
        uint256 ticketId;
        uint256 correctNumbersCount;
    }

    /**
     * @dev Structure that contains the details of a ticket.
     * @param ticketId The unique ID of the ticket.
     * @param numbers The numbers chosen by the player.
     */
    struct TicketDetails {
        uint256 ticketId;
        uint256[] numbers;
    }

    /// @notice The price of a single lottery ticket in tokens
    uint256 public ticketPrice;

    /// @notice The lock duration for ticket refunds
    uint256 public lockDuration;

    /// @notice The current lottery period
    uint256 public currentPeriod;

    /// @notice The next TicketId
    uint256 private nextTicketId;

    /// @notice Mapping from user address to their tickets
    mapping(address => Ticket[]) public tickets;

    /// @notice Mapping from ticket ID to the owner's address
    mapping(uint256 => address) public ticketOwner;

    /// @notice Mapping from lottery period to the winning numbers
    mapping(uint256 => uint256[]) public winningNumbers;

    /// @notice Mapping from lottery period to the draw date
    mapping(uint256 => uint256) public drawDates;

    /// @notice Event emitted when winning numbers are drawn
    /// @param period The lottery period
    /// @param winningNumbers The drawn winning numbers
    event NumbersDrawn(uint256 period, uint256[] winningNumbers);

    /// @notice Event emitted for debugging purposes when all tickets are refunded
    /// @param refundAmount The total refund amount
    /// @param ticketCount The number of tickets refunded
    event refundAllTicketsDebug(uint256 refundAmount, uint256 ticketCount);

    /// @notice Event emitted when a ticket is refunded
    /// @param user The address of the user receiving the refund
    /// @param ticketId The ID of the refunded ticket
    /// @param refundedAmount The amount refunded for the ticket
    event TicketRefunded(address indexed user, uint256 ticketId, uint256 refundedAmount);

    /// @notice Event emitted when a ticket is purchased
    /// @param buyer The address of the buyer
    /// @param ticketId The ID of the purchased ticket
    /// @param numbers The array of numbers on the ticket
    /// @param timestamp The purchase timestamp
    event TicketPurchased(address indexed buyer, uint256 ticketId, uint256[] numbers, uint256 timestamp);

    /**
     * @dev Initializes the contract and sets the sender as the owner.
     * Initializes the token, ticket price, next ticket ID, current period, and lock duration.
     */
    constructor() Ownable(msg.sender) {
        token = IERC20(0x2A944D47944985F746d32e952cEbA7EB909E1d4F);
        ticketPrice = 1000 * 10**18;
        nextTicketId = 1;
        currentPeriod = 0;
        lockDuration = 2592000; // 30 Tage in Sekunden
    }

    /**
     * @notice Buy a ticket for the lottery with a unique set of numbers.
     * @dev Transfers the ticket price from the buyer's address to this contract.
     *      The ticket price is reduced by 2% due to the burn fee imposed by the DAX token.
     *      This fee is automatically burned to decrease the total supply of DAX tokens,
     *      which is not recoverable or redirected to any operational costs.
     * @param _numbers An array of unique numbers representing the lottery ticket.
     * @return ticketId The ID of the purchased ticket.
     * @return numbers The array of numbers that was submitted.
     */
    function buyTicket(uint256[] memory _numbers) public returns (uint256 ticketId, uint256[] memory numbers) {
        require(_numbers.length == 6, "Invalid numbers count");
        validateNumbers(_numbers);

        uint256 pricePaid = ticketPrice - (ticketPrice * 2 / 100);

        require(token.transferFrom(msg.sender, address(this), ticketPrice), "Payment failed");

        Ticket memory newTicket = Ticket({
            id: nextTicketId,
            numbers: _numbers,
            timestamp: block.timestamp,
            pricePaid: pricePaid
        });

        tickets[msg.sender].push(newTicket);
        ticketOwner[nextTicketId] = msg.sender;

        ticketId = nextTicketId;
        numbers = _numbers;
        nextTicketId++;

        emit TicketPurchased(msg.sender, ticketId, numbers, block.timestamp);
        return (ticketId, numbers);
    }

    /**
     * @notice Buys multiple lottery tickets for a given set of number arrays.
     * @dev This function allows the purchase of multiple tickets at once. It requires that the token transfer for the total price of all tickets succeeds before issuing the tickets. Tickets are then recorded in the blockchain with their unique ID, set of numbers, purchase timestamp, and the net price paid after considering any applicable fees.
     * @param _numbersArray An array of number arrays, each representing a single ticket with a unique set of numbers.
     * @return purchasedTickets An array of TicketDetails structs, each containing the ticket ID and the numbers for each purchased ticket.
     * 
     * Requirements:
     * - Each ticket must consist of exactly 6 numbers.
     * - Numbers for each ticket must be unique within that ticket and within the range 1 to 49.
     * - The buyer must have sufficient tokens to cover the total ticket price, and the token transfer from the buyer to the contract must succeed.
     * 
     * Emits a TicketPurchased event for each ticket purchased.
     */
    function buyMultiTickets(uint256[][] memory _numbersArray) public returns (TicketDetails[] memory) {
        require(_numbersArray.length > 0, "No tickets specified");
        require(_numbersArray.length <= 17, "Cannot buy more than 17 tickets at once");

        uint256 totalTicketPrice = ticketPrice * _numbersArray.length;

        require(token.transferFrom(msg.sender, address(this), totalTicketPrice), "Payment failed");

        TicketDetails[] memory purchasedTickets = new TicketDetails[](_numbersArray.length);

        for (uint256 i = 0; i < _numbersArray.length; i++) {
            require(_numbersArray[i].length == 6, "Invalid numbers count for ticket");
            validateNumbers(_numbersArray[i]);

            uint256 pricePaid = ticketPrice - (ticketPrice * 2 / 100); 

            Ticket memory newTicket = Ticket({
                id: nextTicketId,
                numbers: _numbersArray[i],
                timestamp: block.timestamp,
                pricePaid: pricePaid
            });

            tickets[msg.sender].push(newTicket);
            ticketOwner[nextTicketId] = msg.sender;

            purchasedTickets[i] = TicketDetails({
                ticketId: nextTicketId,
                numbers: _numbersArray[i]
            });

            emit TicketPurchased(msg.sender, nextTicketId, _numbersArray[i], block.timestamp);
            nextTicketId++;
        }

        return purchasedTickets;
    }

    /**
     * @notice Validates the numbers in a lottery ticket.
     * @dev Checks that the provided array of numbers for a lottery ticket adheres to the game's rules: the numbers must be within the range 1 to 49, and all numbers in the array must be unique.
     * @param numbers An array of integers representing the numbers on a lottery ticket.
     * 
     * Requirements:
     * - There must be exactly 6 numbers in the array.
     * - Each number must be unique within the array.
     * - Each number must be between 1 and 49, inclusive.
     * 
     * Throws if any of the validation checks fail, preventing the creation or validation of invalid tickets.
     */
    function validateNumbers(uint256[] memory numbers) internal pure {
        require(numbers.length == 6, "Invalid numbers count"); // Check for exactly 6 numbers

        bool[50] memory numberExists; // Tracks if a number has already been used

        for (uint256 i = 0; i < numbers.length; i++) {
            require(numbers[i] >= 1, "Number must be at least 1"); // Ensure number is at least 1
            require(numbers[i] <= 49, "Number must be at most 49"); // Ensure number is at most 49
            require(!numberExists[numbers[i]], "Numbers must be unique"); // Ensure uniqueness

            numberExists[numbers[i]] = true; // Mark number as used
        }
    }

    /**
     * @notice Allows a ticket holder to request a refund for their purchased lottery ticket.
     * @dev Refunds the ticket if it is not within the lock period and if the caller is the ticket owner.
     *      This function handles the verification of ticket ownership, checks against the lock period,
     *      and executes the token transfer for the refund amount. It also manages the removal of the ticket
     *      from the user's ticket array to prevent reuse of the refunded ticket.
     * @param ticketId The unique identifier of the ticket to be refunded.
     * 
     * Requirements:
     * - The caller must be the owner of the ticket.
     * - The ticket must not be within the lock period based on the purchase timestamp plus the lockDuration.
     * 
     * Emits a TicketRefunded event upon a successful refund.
     */
    function refundTicket(uint256 ticketId) public nonReentrant {
        require(ticketOwner[ticketId] == msg.sender, "You do not own this ticket");

        Ticket[] storage userTickets = tickets[msg.sender];
        for (uint256 i = 0; i < userTickets.length; i++) {
            if (userTickets[i].id == ticketId) {
                require(block.timestamp >= userTickets[i].timestamp + lockDuration, "Ticket locked");

                uint256 pricePaid = userTickets[i].pricePaid;
                deleteTicket(userTickets, i);

                require(token.transfer(msg.sender, pricePaid), "Refund failed");
                emit TicketRefunded(msg.sender, ticketId, pricePaid);
                delete ticketOwner[ticketId];
                break;
            }
        }
    }

    /**
     * @notice Refunds all eligible tickets for the caller.
     * @dev A ticket is eligible for a refund if the current time has surpassed the lock duration from the ticket's timestamp.
     *      This function handles the refund process by updating the tickets array for the user, recalculating the refund amount,
     *      and managing the state of each ticket to ensure tickets are not reused.
     * 
     * Emits a refundAllTicketsDebug event that logs the total refund amount and the number of tickets refunded.
     * 
     * Requirements:
     * - Only tickets outside of their lock period are considered for refunds.
     * 
     * Reverts if no tickets are eligible for refund or if the token transfer for the refund fails.
     */
    function refundAllTickets() public nonReentrant {
        Ticket[] storage userTickets = tickets[msg.sender];
        uint256 refundAmount = 0;
        uint256 i = 0;

        while (i < userTickets.length) {
            if (block.timestamp >= userTickets[i].timestamp + lockDuration) {
                refundAmount += userTickets[i].pricePaid;
                delete ticketOwner[userTickets[i].id];
                deleteTicket(userTickets, i);
            } else {
                i++;
            }
        }

        if (refundAmount > 0) {
            emit refundAllTicketsDebug(refundAmount, userTickets.length);
            require(token.transfer(msg.sender, refundAmount), "Refund failed: token transfer failed");
        } else {
            revert("No tickets eligible for refund or refund period not yet expired.");
        }
    }

    /**
     * @notice Deletes a ticket from the user's list of tickets.
     * @dev The function removes the ticket at the specified index from the user's ticket array by replacing it with the last element and then reducing the array length.
     * @param userTickets The array of tickets belonging to the user.
     * @param index The index of the ticket to be deleted.
     */
    function deleteTicket(Ticket[] storage userTickets, uint256 index) internal {
        require(index < userTickets.length, "Index out of bounds");
        userTickets[index] = userTickets[userTickets.length - 1];
        userTickets.pop();
    }

    /**
     * @notice Draws winning numbers for the current lottery period and advances to the next period.
     * @dev Generates a set of 6 unique winning numbers between 1 and 49, stores them in the `winningNumbers` mapping under the current lottery period index,
     *      and increments the `currentPeriod` to transition to the next lottery cycle.
     * 
     * Emits a NumbersDrawn event upon drawing the numbers.
     */
    function drawWinningNumbers() public onlyOwner {
        uint256[] memory numbers = new uint256[](6);
        uint256 seed = uint256(blockhash(block.number - 1));
        
        for (uint256 i = 0; i < numbers.length; i++) {
            seed = uint256(keccak256(abi.encodePacked(seed, i)));
            numbers[i] = seed % 49 + 1;

            // Duplikatprüfung
            for (uint256 j = 0; j < i; j++) {
                if (numbers[i] == numbers[j]) {
                    i--;
                    break;
                }
            }
        }

        winningNumbers[currentPeriod] = numbers;
        drawDates[currentPeriod] = block.timestamp;
        emit NumbersDrawn(currentPeriod, numbers);
        currentPeriod++;
    }

    /**
     * @notice Retrieves a paginated list of tickets for a user.
     * @param user The address of the user whose tickets are to be retrieved.
     * @param start The starting index of the tickets to retrieve.
     * @param limit The maximum number of tickets to retrieve.
     * @return An array of tickets belonging to the user within the specified range.
     */
    function getUserTickets(address user, uint256 start, uint256 limit) public view returns (Ticket[] memory) {
        require(start < tickets[user].length, "Start index out of bounds");
        uint256 end = start + limit;
        if (end > tickets[user].length) {
            end = tickets[user].length;
        }

        Ticket[] memory userTickets = new Ticket[](end - start);
        uint256 index = 0;
        for (uint256 i = start; i < end; i++) {
            userTickets[index] = tickets[user][i];
            index++;
        }
        return userTickets;
    }

    /**
     * @notice Retrieves the total number of tickets owned by a user.
     * @param user The address of the user whose ticket count is to be retrieved.
     * @return The total number of tickets owned by the user.
     */
    function getCountUserTickets(address user) public view returns (uint256) {
        return tickets[user].length;
    }

    /**
     * @notice Sets a new lock duration for ticket refunds.
     * @param _newDuration The new lock duration in seconds.
     */
    function setLockDuration(uint256 _newDuration) public onlyOwner {
        lockDuration = _newDuration;
    }

    /**
     * @notice Retrieves the current lock duration for ticket refunds.
     * @return The current lock duration in seconds.
     */
    function getLockDuration() public view returns (uint256) {
        return lockDuration;
    }

    /**
     * @notice Retrieves the winning numbers and draw date for a specific lottery period.
     * @param period The lottery period to retrieve the draw history for.
     * @return A tuple containing the winning numbers and the draw date for the specified period.
     */
    function getDrawHistory(uint256 period) public view returns (uint256[] memory, uint256) {
        return (winningNumbers[period - 1], drawDates[period - 1]);
    }

    /**
     * @notice Output of the current lottery numbers from the current period.
     * @return The winning numbers of the current period.
     */
    function getCurrentWinningNumbers() public view returns (uint256[] memory) {
        return winningNumbers[currentPeriod - 1];
    }

    /**
     * @notice Allows the operator to change the ticket price.
     * @param _newPrice The new ticket price.
     */
    function setTicketPrice(uint256 _newPrice) public onlyOwner {
        ticketPrice = _newPrice;
    }

    /**
     * @notice Checks for winning tickets for a user within a specified range.
     * @param user The address of the user whose tickets are to be checked.
     * @param start The starting index of the tickets to check.
     * @param limit The maximum number of tickets to check.
     * @return An array of WinResult structs containing the results for each ticket checked.
     */
    function checkForWins(address user, uint256 start, uint256 limit) public view returns (WinResult[] memory) {
        Ticket[] memory userTickets = tickets[user];
        uint256 end = start + limit;
        if (end > userTickets.length) {
            end = userTickets.length;
        }

        uint256 count = end - start;
        WinResult[] memory results = new WinResult[](count);
        uint256[] memory winningNumbersForPeriod = winningNumbers[currentPeriod - 1];
        uint256 drawDate = drawDates[currentPeriod - 1];

        uint256 index = 0;
        for (uint256 i = start; i < end; i++) {
            if (userTickets[i].timestamp < drawDate) {
                uint256 matchCount = 0;
                uint256[] memory ticketNumbers = userTickets[i].numbers;

                for (uint256 j = 0; j < ticketNumbers.length; j++) {
                    for (uint256 k = 0; k < winningNumbersForPeriod.length; k++) {
                        if (ticketNumbers[j] == winningNumbersForPeriod[k]) {
                            matchCount++;
                        }
                    }
                }

                results[index] = WinResult({
                    ticketId: userTickets[i].id,
                    correctNumbersCount: matchCount
                });
            } else {
                results[index] = WinResult({
                    ticketId: userTickets[i].id,
                    correctNumbersCount: 0
                });
            }
            index++;
        }

        return results;
    }

    /**
     * @notice Checks all tickets against the winning numbers for the current period and returns a list of results for each ticket.
     * @dev This function can only be called by the owner of the contract. It iterates through all tickets issued up to the last ticket ID and compares each ticket's numbers to the winning numbers of the current period. If a ticket's numbers match any of the winning numbers and was purchased before the draw date, it is considered for the results.
     * @return results An array of CheckResults structs, each containing the results for an individual ticket. Each result includes the ticket ID, the owner of the ticket, the count of correct numbers matched, and an array of the matched numbers themselves.
     */
    function checkAllTickets(uint256 start, uint256 limit) public view onlyOwner returns (CheckResults[] memory) {
        uint256 totalTickets = nextTicketId - 1;
        uint256 end = start + limit;
        if (end > totalTickets) {
            end = totalTickets;
        }

        uint256 count = 0;
        uint256[] memory winningNumbersForPeriod = winningNumbers[currentPeriod - 1];
        uint256 drawDate = drawDates[currentPeriod - 1];

        for (uint256 i = start; i < end; i++) {
            address owner = ticketOwner[i];
            Ticket[] storage userTickets = tickets[owner];
            for (uint256 j = 0; j < userTickets.length; j++) {
                if (userTickets[j].id == i && userTickets[j].numbers.length > 0 && userTickets[j].timestamp < drawDate) {
                    count++;
                }
            }
        }

        CheckResults[] memory tempResults = new CheckResults[](count);
        uint256 index = 0;

        for (uint256 i = start; i < end; i++) {
            address owner = ticketOwner[i];
            Ticket[] storage userTickets = tickets[owner];
            for (uint256 j = 0; j < userTickets.length; j++) {
                if (userTickets[j].id == i && userTickets[j].numbers.length > 0 && userTickets[j].timestamp < drawDate) {
                    uint256[] memory tempCorrectNumbers = new uint256[](6);
                    uint256 matchCount = 0;

                    for (uint256 k = 0; k < userTickets[j].numbers.length; k++) {
                        for (uint256 l = 0; l < winningNumbersForPeriod.length; l++) {
                            if (userTickets[j].numbers[k] == winningNumbersForPeriod[l]) {
                                tempCorrectNumbers[matchCount] = userTickets[j].numbers[k];
                                matchCount++;
                            }
                        }
                    }

                    CheckResults memory result = CheckResults({
                        ticketId: userTickets[j].id,
                        owner: owner,
                        correctNumbersCount: matchCount,
                        correctNumbers: new uint256[](matchCount)
                    });

                    for (uint256 m = 0; m < matchCount; m++) {
                        result.correctNumbers[m] = tempCorrectNumbers[m];
                    }

                    tempResults[index++] = result;
                }
            }
        }

        return tempResults;
    }

    /**
     * @notice Calculates how many tickets a user can return that are outside the lock period.
     * @param user The address of the user whose tickets are to be checked.
     * @return count The number of tickets that can be returned.
     */
    function countRefundableTickets(address user) public view returns (uint256 count) {
        Ticket[] memory userTickets = tickets[user];
        count = 0;
        for (uint256 i = 0; i < userTickets.length; i++) {
            if (block.timestamp >= userTickets[i].timestamp + lockDuration) {
                count++;
            }
        }
        return count;
    }

    /**
     * @dev Retrieves a comprehensive list of all tickets issued by the contract.
     * This function is restricted to the contract owner and provides a complete snapshot 
     * of all tickets, including detailed information such as ticket numbers, purchase timestamps,
     * the amount paid for each ticket, and the owner's address. It is primarily used for administrative
     * purposes such as auditing and tracking ticket distribution.
     *
     * @return allTickets An array of ExtendedTicket structs, where each ExtendedTicket contains:
     *         - id: The unique identifier of the ticket.
     *         - numbers: An array of numbers chosen for the lottery ticket.
     *         - timestamp: The blockchain timestamp when the ticket was purchased.
     *         - pricePaid: The actual price paid for the ticket after any fees.
     *         - owner: The address of the ticket owner.
     */
    function viewAllTickets(uint256 start, uint256 limit) public view onlyOwner returns (ExtendedTicket[] memory) {
        uint256 totalTickets = nextTicketId;
        uint256 end = start + limit;
        if (end > totalTickets) {
            end = totalTickets;
        }

        ExtendedTicket[] memory tempTickets = new ExtendedTicket[](limit);
        uint256 index = 0;

        for (uint256 i = start; i < end; i++) {
            address owner = ticketOwner[i];
            Ticket[] storage userTickets = tickets[owner];
            for (uint256 j = 0; j < userTickets.length; j++) {
                if (userTickets[j].id == i) {
                    tempTickets[index] = ExtendedTicket({
                        id: userTickets[j].id,
                        numbers: userTickets[j].numbers,
                        timestamp: userTickets[j].timestamp,
                        pricePaid: userTickets[j].pricePaid,
                        owner: owner
                    });
                    index++;
                    if (index == limit) {
                        return tempTickets;
                    }
                }
            }
        }

        // Resize the array to the actual number of tickets found
        ExtendedTicket[] memory resultTickets = new ExtendedTicket[](index);
        for (uint256 i = 0; i < index; i++) {
            resultTickets[i] = tempTickets[i];
        }

        return resultTickets;
    }

    /**
     * @notice Retrieves the total number of tickets issued by the contract.
     * @return The total number of tickets.
     */
    function getTotalTickets() public view returns (uint256) {
        return nextTicketId - 1;
    }

    /**
     * @notice Counts the active tickets in the contract.
     * @return The number of active tickets.
     */
    function countActivTickets() public view returns (uint256) {
        uint256 count = 0;
        address[] memory owners = getAllOwners(); // Helper function to get all unique ticket owners
        for (uint256 i = 0; i < owners.length; i++) {
            address owner = owners[i];
            Ticket[] storage userTickets = tickets[owner];
            for (uint256 j = 0; j < userTickets.length; j++) {
                if (userTickets[j].numbers.length > 0) {
                    count++;
                }
            }
        }
        return count;
    }

    /**
     * @notice Retrieves all unique ticket owners.
     * @return An array of addresses of unique ticket owners.
     */
    function getAllOwners() internal view returns (address[] memory) {
        address[] memory owners = new address[](nextTicketId);
        uint256 ownerCount = 0;
        for (uint256 i = 0; i < nextTicketId; i++) {
            address owner = ticketOwner[i];
            bool alreadyAdded = false;
            for (uint256 j = 0; j < ownerCount; j++) {
                if (owners[j] == owner) {
                    alreadyAdded = true;
                    break;
                }
            }
            if (!alreadyAdded) {
                owners[ownerCount] = owner;
                ownerCount++;
            }
        }
        // Resize the array to the actual number of unique owners
        address[] memory uniqueOwners = new address[](ownerCount);
        for (uint256 i = 0; i < ownerCount; i++) {
            uniqueOwners[i] = owners[i];
        }
        return uniqueOwners;
    }
}
