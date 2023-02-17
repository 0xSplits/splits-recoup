// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {LibSort} from "solady/utils/LibSort.sol";
import {ISplitMain} from "../src/interfaces/ISplitMain.sol";
import {IWaterfallModuleFactory} from "../src/interfaces/IWaterfallModuleFactory.sol";

import {Recoup} from "../src/Recoup.sol";

contract RecoupTest is Test {
    using LibSort for address[];

    event CreateRecoup(address waterfallModule);

    uint256 constant BLOCK_NUMBER = 15684597;

    ISplitMain public splitMain;
    IWaterfallModuleFactory public waterfallModuleFactory;

    uint32 public distributorFee;
    address public nonWaterfallRecipient;
    address[][] public recipients;
    uint32[][] public percentAllocations;
    uint256[] public thresholds;

    Recoup recoup;

    function setUp() public {
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(MAINNET_RPC_URL, BLOCK_NUMBER);

        splitMain = ISplitMain(0x2ed6c4B5dA6378c7897AC67Ba9e43102Feb694EE);
        waterfallModuleFactory = IWaterfallModuleFactory(0x4Df01754eBd055498C8087b1e9a5c7a9ad19b0F6);

        nonWaterfallRecipient = makeAddr("nonWaterfallRecipient");
        (recipients, percentAllocations, thresholds) = generateTranches(2, 2);

        distributorFee = 2e4;

        recoup = new Recoup(address(splitMain), address(waterfallModuleFactory));
    }

    /// -----------------------------------------------------------------------
    /// correctness tests - basic
    /// -----------------------------------------------------------------------

    function testCan_createRecoupWithAllSplits() public {
        recoup.createRecoup(
            address(0), nonWaterfallRecipient, distributorFee, recipients, percentAllocations, thresholds
        );
    }

    function testCan_createRecoupWithAllSingleAddresses() public {
        (recipients, percentAllocations, thresholds) = generateTranches(2, 1);
        recoup.createRecoup(
            address(0), nonWaterfallRecipient, distributorFee, recipients, percentAllocations, thresholds
        );
    }

    function testCan_createRecoupWithSomeSplits() public {
        recipients[1] = new address[](1);
        recipients[1][0] = makeAddr("singleRecipient");
        percentAllocations[1] = new uint32[](1);
        percentAllocations[1][0] = 1e6;
        recoup.createRecoup(
            address(0), nonWaterfallRecipient, distributorFee, recipients, percentAllocations, thresholds
        );
    }

    function testCan_emitOnCreate() public {
        vm.expectEmit(false, false, false, false);
        emit CreateRecoup(address(0xdead));
        recoup.createRecoup(
            address(0), nonWaterfallRecipient, distributorFee, recipients, percentAllocations, thresholds
        );
    }

    function testCannot_createWithMismatchedTrancheDataLengths() public {
        recipients = generateTrancheRecipients(3, 2);
        vm.expectRevert(Recoup.InvalidRecoup__RecipientsAndPercentAllocationsMismatch.selector);
        recoup.createRecoup(
            address(0), nonWaterfallRecipient, distributorFee, recipients, percentAllocations, thresholds
        );
    }

    function testCannot_createWithMismatchedSplitDataLengths() public {
        recipients[0] = new address[](1);
        recipients[0][0] = makeAddr("recipient");
        vm.expectRevert(
            abi.encodeWithSelector(Recoup.InvalidRecoup__TrancheAccountsAndPercentAllocationsMismatch.selector, 0)
        );
        recoup.createRecoup(
            address(0), nonWaterfallRecipient, distributorFee, recipients, percentAllocations, thresholds
        );
    }

    function testCannot_createWithEmptyTrancheRecipients() public {
        recipients[0] = new address[](0);
        percentAllocations[0] = new uint32[](0);
        vm.expectRevert(abi.encodeWithSelector(Recoup.InvalidRecoup__TooFewAccounts.selector, 0));
        recoup.createRecoup(
            address(0), nonWaterfallRecipient, distributorFee, recipients, percentAllocations, thresholds
        );
    }

    function testCannot_createWithSingleAddressInvalidPercentAllocation() public {
        recipients[0] = new address[](1);
        recipients[0][0] = makeAddr("recipient");
        percentAllocations[0] = new uint32[](1);
        percentAllocations[0][0] = 1e5;
        vm.expectRevert(abi.encodeWithSelector(Recoup.InvalidRecoup__SingleAddressPercentAllocation.selector, 0, 1e5));
        recoup.createRecoup(
            address(0), nonWaterfallRecipient, distributorFee, recipients, percentAllocations, thresholds
        );
    }

    /// -----------------------------------------------------------------------
    /// correctness tests - fuzzing
    /// -----------------------------------------------------------------------

    function testCan_createRecoups(uint8 _numTranches, uint8 _splitLength) public {
        uint256 numTranches = bound(_numTranches, 2, 50);
        uint256 splitLength = bound(_splitLength, 1, 10);

        (recipients, percentAllocations, thresholds) = generateTranches(numTranches, splitLength);

        recoup.createRecoup(
            address(0), nonWaterfallRecipient, distributorFee, recipients, percentAllocations, thresholds
        );
    }

    /// -----------------------------------------------------------------------
    /// helper fns
    /// -----------------------------------------------------------------------

    function generateTranches(uint256 numTranches, uint256 splitLength)
        internal
        pure
        returns (address[][] memory _recipients, uint32[][] memory _percentAllocations, uint256[] memory _thresholds)
    {
        _recipients = generateTrancheRecipients(numTranches, splitLength);
        _percentAllocations = generateTranchePercentAllocations(numTranches, splitLength);
        _thresholds = generateTrancheThresholds(numTranches - 1);
    }

    function generateTrancheRecipients(uint256 numRecipients, uint256 splitLength)
        internal
        pure
        returns (address[][] memory _recipients)
    {
        _recipients = new address[][](numRecipients);
        for (uint256 i = 0; i < numRecipients; i++) {
            address[] memory _currentRecipients = new address[](splitLength);
            for (uint256 j = 0; j < splitLength; j++) {
                _currentRecipients[j] = address(uint160((j + 1) * (i + 1)));
            }
            _currentRecipients.sort();
            _currentRecipients.uniquifySorted();
            _recipients[i] = _currentRecipients;
        }
    }

    function generateTranchePercentAllocations(uint256 numAccounts, uint256 splitLength)
        internal
        pure
        returns (uint32[][] memory allocations)
    {
        allocations = new uint32[][](numAccounts);
        for (uint256 i = 0; i < numAccounts; i++) {
            uint256 _total = 0;
            uint32[] memory _currentPercents = new uint32[](splitLength);
            for (uint256 j = 0; j < splitLength; j++) {
                _currentPercents[j] = uint32(1e6 / splitLength);
                _total += _currentPercents[j];
            }
            _currentPercents[0] += uint32(1e6 - _total);
            allocations[i] = _currentPercents;
        }
    }

    function generateTrancheThresholds(uint256 numThresholds) internal pure returns (uint256[] memory _thresholds) {
        _thresholds = new uint256[](numThresholds);
        for (uint256 i = 0; i < numThresholds; i++) {
            _thresholds[i] = (i + 1) * 1 ether;
        }
    }
}
