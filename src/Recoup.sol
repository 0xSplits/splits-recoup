// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ISplitMain} from "./interfaces/ISplitMain.sol";
import {IWaterfallModuleFactory} from "./interfaces/IWaterfallModuleFactory.sol";
import {IWaterfallModule} from "./interfaces/IWaterfallModule.sol";

/// @title Recoup
/// @author 0xSplits
/// @notice A contract for efficiently combining splits together with a waterfall
contract Recoup {
    /// -----------------------------------------------------------------------
    /// errors
    /// -----------------------------------------------------------------------

    /// Invalid recipient & percent allocation lengths; must be equal
    error InvalidRecoup__RecipientsAndPercentAllocationsMismatch();

    /// Invalid number of accounts for a recoup tranche; must be at least one
    error InvalidRecoup__TooFewAccounts(uint256 index);

    error InvalidRecoup__AccountsAndPercentAllocationsMismatch(uint256 index);

    /// Invalid percent allocation for a single address; must equal PERCENTAGE_SCALE
    error InvalidRecoup__SingleAddressPercentAllocation(uint256 index, uint32 percentAllocation);

    /// -----------------------------------------------------------------------
    /// storage
    /// -----------------------------------------------------------------------

    ISplitMain public immutable splitMain;
    IWaterfallModuleFactory public immutable waterfallModuleFactory;

    uint256 public constant PERCENTAGE_SCALE = 1e6;
    // uint256 internal constant MAX_DISTRIBUTOR_FEE = 1e5;

    /// -----------------------------------------------------------------------
    /// constructor
    /// -----------------------------------------------------------------------

    constructor(address _splitMain, address _waterfallModuleFactory) {
        splitMain = ISplitMain(_splitMain);
        waterfallModuleFactory = IWaterfallModuleFactory(_waterfallModuleFactory);
    }

    /// -----------------------------------------------------------------------
    /// functions
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// functions - public & external
    /// -----------------------------------------------------------------------

    /// Creates a waterfall module and possibly multiple splits given the input parameters
    /// @param token Address of ERC20 to waterfall (0x0 used for ETH)
    /// @param nonWaterfallRecipient Address to recover non-waterfall tokens to
    /// @param distributorFee Fee paid out to the distributor of each split
    /// @param recipients Addresses to optionally create splits for / waterfall payments to
    /// @param percentAllocations Allocations for each address within a waterfall tranche
    /// @param thresholds Absolute payment thresholds for waterfall tranches
    /// (last recipient has no threshold & receives all residual flows)
    /// @dev A single address in a recipient array with a matching single 1e6 value in a percentAllocations array means that tranche will be a single address and not a split
    function createRecoup(
      address token,
      address nonWaterfallRecipient, // Worth having this? Don't think we expose it in our ui currently, so can't see us adding it for this (but maybe good to have as an option for future ui updates)
      uint32 distributorFee, // Worth even having this? Should it always be 0? If the waterfall has no distribution incentive, seems like minimal gain to have it on the splits
      address[][] calldata recipients,
      uint32[][] calldata percentAllocations,
      uint256[] calldata thresholds
    ) external {
      /// checks

      uint256 recipientsLength = recipients.length;

      // ensure recipients array and percent allocations array match in length
      if (recipientsLength != percentAllocations.length) {
        revert InvalidRecoup__RecipientsAndPercentAllocationsMismatch();
      }

      uint256 i = 0;
      for (; i < recipientsLength;) {
        // TODO: better way to setup these checks?

        uint256 recipientsIndexLength = recipients[i].length;
        if (recipientsIndexLength != percentAllocations[i].length) {
          revert InvalidRecoup__AccountsAndPercentAllocationsMismatch(i);
        }
        if (recipientsIndexLength == 0) {
          revert InvalidRecoup__TooFewAccounts(i);
        }
        if (recipientsIndexLength == 1 && percentAllocations[i][0] != PERCENTAGE_SCALE) {
          revert InvalidRecoup__SingleAddressPercentAllocation(i, percentAllocations[i][0]);
        }
        // Other recipient/percent allocation combos are splits and will get validated in the create split call

        unchecked {
          ++i;
        }
      }

      /// effects
      address[] memory waterfallRecipients = new address[](recipientsLength);
      
      // Create splits
      i = 0;
      for (; i < recipientsLength;) {
        if (recipients[i].length == 1) {
          waterfallRecipients[i] = recipients[i][0];
        } else {
          // Will fail if it's an immutable split that already exists. The caller
          // should just pass in the split address (with percent = 100%) in that case
          waterfallRecipients[i] = splitMain.createSplit({
              accounts: recipients[i],
              percentAllocations: percentAllocations[i],
              distributorFee: distributorFee,
              controller: address(0)
          });
        }

        unchecked {
          ++i;
        }
      }

      // Create waterfall
      IWaterfallModule wm = waterfallModuleFactory.createWaterfallModule({
          token: token,
          nonWaterfallRecipient: nonWaterfallRecipient,
          recipients: waterfallRecipients,
          thresholds: thresholds
      });

      // TODO: do i need the created split addresses here too? Technically subgraph can look those up from the waterfall I think.
      emit CreateRecoup(address(wm));
    }
}
