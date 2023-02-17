// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {Recoup} from "../src/Recoup.sol";

contract RecoupScript is Script {
    function run() external {
        uint256 privKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privKey);

        new Recoup{salt: keccak256("0xSplits.recoup.v1")}(0x2ed6c4B5dA6378c7897AC67Ba9e43102Feb694EE, 0x4Df01754eBd055498C8087b1e9a5c7a9ad19b0F6);

        vm.stopBroadcast();
    }
}
