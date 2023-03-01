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
    event CreateWaterfallModule(
        address indexed waterfallModule,
        address token,
        address nonWaterfallRecipient,
        address[] recipients,
        uint256[] thresholds
    );

    uint256 constant BLOCK_NUMBER = 15684597;

    ISplitMain public splitMain;
    IWaterfallModuleFactory public waterfallModuleFactory;

    address public nonWaterfallRecipientAddress;
    uint256 public nonWaterfallRecipientTrancheIndex;
    uint256 public tranchesLength;
    uint256 public splitRecipientsLength;

    Recoup recoup;

    function setUp() public {
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(MAINNET_RPC_URL, BLOCK_NUMBER);

        splitMain = ISplitMain(0x2ed6c4B5dA6378c7897AC67Ba9e43102Feb694EE);
        waterfallModuleFactory = IWaterfallModuleFactory(0x4Df01754eBd055498C8087b1e9a5c7a9ad19b0F6);

        nonWaterfallRecipientAddress = makeAddr("nonWaterfallRecipient");
        nonWaterfallRecipientTrancheIndex = 2;
        tranchesLength = 2;
        splitRecipientsLength = 2;

        recoup = new Recoup(address(splitMain), address(waterfallModuleFactory));
    }

    /// -----------------------------------------------------------------------
    /// correctness tests - basic
    /// -----------------------------------------------------------------------

    function testCan_createRecoupWithAllSplits() public {
        // TODO: anyway to not repeat this in all the tests? Solidity complains if I assign to storage and then pass
        // through as an arg. Some way to cast to memory before calling createRecoup maybe?
        (Recoup.Tranche[] memory tranches, uint256[] memory thresholds) =
            generateTranches(tranchesLength, splitRecipientsLength);
        recoup.createRecoup(
            address(0), nonWaterfallRecipientAddress, nonWaterfallRecipientTrancheIndex, tranches, thresholds
        );
    }

    function testCan_createRecoupWithAllSingleAddresses() public {
        (Recoup.Tranche[] memory tranches, uint256[] memory thresholds) = generateTranches(tranchesLength, 1);
        recoup.createRecoup(
            address(0), nonWaterfallRecipientAddress, nonWaterfallRecipientTrancheIndex, tranches, thresholds
        );
    }

    function testCan_createRecoupWithSomeSplits() public {
        (Recoup.Tranche[] memory tranches, uint256[] memory thresholds) =
            generateTranches(tranchesLength, splitRecipientsLength);
        tranches[1].recipients = new address[](1);
        tranches[1].recipients[0] = makeAddr("singleRecipient");
        tranches[1].percentAllocations = new uint32[](1);
        tranches[1].percentAllocations[0] = 1e6;

        recoup.createRecoup(
            address(0), nonWaterfallRecipientAddress, nonWaterfallRecipientTrancheIndex, tranches, thresholds
        );
    }

    // TODO: distributor fee and controller tests?

    function testCan_setNonWaterfallRecipientByAddress() public {
        (Recoup.Tranche[] memory tranches, uint256[] memory thresholds) = generateTranches(2, 1);

        vm.expectEmit(false, false, false, true);
        address[] memory _waterfallEventAddresses = new address[](2);
        _waterfallEventAddresses[0] = tranches[0].recipients[0];
        _waterfallEventAddresses[1] = tranches[1].recipients[0];
        emit CreateWaterfallModule(
            address(0), address(0), nonWaterfallRecipientAddress, _waterfallEventAddresses, thresholds
            );

        recoup.createRecoup(
            address(0), nonWaterfallRecipientAddress, nonWaterfallRecipientTrancheIndex, tranches, thresholds
        );
    }

    function testCan_setNonWaterfallRecipientByTrancheIndex() public {
        address _nonWaterfallRecipient = makeAddr("nonWaterfallRecipientTrancheIndex");

        (Recoup.Tranche[] memory tranches, uint256[] memory thresholds) = generateTranches(2, 1);
        tranches[1].recipients[0] = _nonWaterfallRecipient;

        vm.expectEmit(false, false, false, true);
        address[] memory _waterfallEventAddresses = new address[](2);
        _waterfallEventAddresses[0] = tranches[0].recipients[0];
        _waterfallEventAddresses[1] = tranches[1].recipients[0];
        emit CreateWaterfallModule(address(0), address(0), _nonWaterfallRecipient, _waterfallEventAddresses, thresholds);

        recoup.createRecoup(address(0), address(0), 1, tranches, thresholds);
    }

    function testCan_emitOnCreate() public {
        (Recoup.Tranche[] memory tranches, uint256[] memory thresholds) =
            generateTranches(tranchesLength, splitRecipientsLength);

        vm.expectEmit(false, false, false, false);
        emit CreateRecoup(address(0xdead));
        recoup.createRecoup(
            address(0), nonWaterfallRecipientAddress, nonWaterfallRecipientTrancheIndex, tranches, thresholds
        );
    }

    function testCannot_createWithNonWaterfallRecipientIndexTooLarge() public {
        (Recoup.Tranche[] memory tranches, uint256[] memory thresholds) =
            generateTranches(tranchesLength, splitRecipientsLength);

        vm.expectRevert(
            abi.encodeWithSelector(Recoup.InvalidRecoup__NonWaterfallRecipientTrancheIndexTooLarge.selector)
        );
        recoup.createRecoup(address(0), nonWaterfallRecipientAddress, 3, tranches, thresholds);
    }

    function testCannot_createWithNonWaterfallRecipientSetTwice() public {
        (Recoup.Tranche[] memory tranches, uint256[] memory thresholds) =
            generateTranches(tranchesLength, splitRecipientsLength);

        vm.expectRevert(abi.encodeWithSelector(Recoup.InvalidRecoup__NonWaterfallRecipientSetTwice.selector));
        recoup.createRecoup(address(0), nonWaterfallRecipientAddress, 0, tranches, thresholds);
    }

    function testCannot_createWithMismatchedSplitDataLengths() public {
        (Recoup.Tranche[] memory tranches, uint256[] memory thresholds) =
            generateTranches(tranchesLength, splitRecipientsLength);

        tranches[0].recipients = new address[](1);
        tranches[0].recipients[0] = makeAddr("recipient");
        vm.expectRevert(
            abi.encodeWithSelector(Recoup.InvalidRecoup__TrancheAccountsAndPercentAllocationsMismatch.selector, 0)
        );
        recoup.createRecoup(
            address(0), nonWaterfallRecipientAddress, nonWaterfallRecipientTrancheIndex, tranches, thresholds
        );
    }

    function testCannot_createWithEmptyTrancheRecipients() public {
        (Recoup.Tranche[] memory tranches, uint256[] memory thresholds) =
            generateTranches(tranchesLength, splitRecipientsLength);

        tranches[0].recipients = new address[](0);
        tranches[0].percentAllocations = new uint32[](0);
        vm.expectRevert(abi.encodeWithSelector(Recoup.InvalidRecoup__TooFewAccounts.selector, 0));
        recoup.createRecoup(
            address(0), nonWaterfallRecipientAddress, nonWaterfallRecipientTrancheIndex, tranches, thresholds
        );
    }

    function testCannot_createWithSingleAddressInvalidPercentAllocation() public {
        (Recoup.Tranche[] memory tranches, uint256[] memory thresholds) =
            generateTranches(tranchesLength, splitRecipientsLength);

        tranches[0].recipients = new address[](1);
        tranches[0].recipients[0] = makeAddr("recipient");
        tranches[0].percentAllocations = new uint32[](1);
        tranches[0].percentAllocations[0] = 1e5;
        vm.expectRevert(abi.encodeWithSelector(Recoup.InvalidRecoup__SingleAddressPercentAllocation.selector, 0, 1e5));
        recoup.createRecoup(
            address(0), nonWaterfallRecipientAddress, nonWaterfallRecipientTrancheIndex, tranches, thresholds
        );
    }

    /// -----------------------------------------------------------------------
    /// correctness tests - fuzzing
    /// -----------------------------------------------------------------------

    function testCan_createRecoups(uint8 _numTranches, uint8 _splitLength) public {
        uint256 numTranches = bound(_numTranches, 2, 50);
        uint256 splitLength = bound(_splitLength, 1, 10);

        (Recoup.Tranche[] memory tranches, uint256[] memory thresholds) = generateTranches(numTranches, splitLength);

        recoup.createRecoup(address(0), nonWaterfallRecipientAddress, numTranches, tranches, thresholds);
    }

    /// -----------------------------------------------------------------------
    /// helper fns
    /// -----------------------------------------------------------------------

    function generateTranches(uint256 numTranches, uint256 splitLength)
        internal
        pure
        returns (Recoup.Tranche[] memory _tranches, uint256[] memory _thresholds)
    {
        _tranches = new Recoup.Tranche[](numTranches);
        for (uint256 i = 0; i < numTranches; i++) {
            _tranches[i].recipients = generateTrancheRecipients(i, splitLength);
            _tranches[i].percentAllocations = generateTranchePercentAllocations(splitLength);
            _tranches[i].controller = address(0);
            _tranches[i].distributorFee = 1e4;
        }
        _thresholds = generateTrancheThresholds(numTranches - 1);
    }

    function generateTrancheRecipients(uint256 trancheIndex, uint256 splitLength)
        internal
        pure
        returns (address[] memory _recipients)
    {
        _recipients = new address[](splitLength);
        for (uint256 i = 0; i < splitLength; i++) {
            _recipients[i] = address(uint160((trancheIndex + 1) * (i + 1)));
        }
        _recipients.sort();
        _recipients.uniquifySorted();
    }

    function generateTranchePercentAllocations(uint256 splitLength)
        internal
        pure
        returns (uint32[] memory _allocations)
    {
        uint256 _total = 0;
        _allocations = new uint32[](splitLength);
        for (uint256 i = 0; i < splitLength; i++) {
            _allocations[i] = uint32(1e6 / splitLength);
            _total += _allocations[i];
        }
        _allocations[0] += uint32(1e6 - _total);
    }

    function generateTrancheThresholds(uint256 numThresholds) internal pure returns (uint256[] memory _thresholds) {
        _thresholds = new uint256[](numThresholds);
        for (uint256 i = 0; i < numThresholds; i++) {
            _thresholds[i] = (i + 1) * 1 ether;
        }
    }
}
