use staking_test::types::{Amount, Epoch, Index, Inflation, Version};
use starknet::ContractAddress;
use starkware_utils::constants::WEEK;
use starkware_utils::types::time::time::TimeDelta;

pub(crate) const DEFAULT_EXIT_WAIT_WINDOW: TimeDelta = TimeDelta { seconds: 3 * WEEK };
pub(crate) const MAX_EXIT_WAIT_WINDOW: TimeDelta = TimeDelta { seconds: 12 * WEEK };
pub(crate) const BASE_VALUE: Index = 10_000_000_000_000_000_000_000_000_000; // 10**28
pub(crate) const STRK_IN_FRIS: Amount = 1_000_000_000_000_000_000; // 10**18
pub(crate) const DEFAULT_C_NUM: Inflation = 160;
pub(crate) const MAX_C_NUM: Inflation = 500;
pub(crate) const C_DENOM: Inflation = 10_000;
pub(crate) const MIN_ATTESTATION_WINDOW: u16 = 11;
pub(crate) const STARTING_EPOCH: Epoch = 0;
pub(crate) const PREV_CONTRACT_VERSION: Version = '0';
pub(crate) const STRK_TOKEN_ADDRESS: ContractAddress =
    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d
    .try_into()
    .unwrap();
