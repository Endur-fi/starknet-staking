use staking_test::types::{Amount, Epoch, Index, Inflation, Version};
use starkware_utils::constants::WEEK;
use starkware_utils::types::time::time::TimeDelta;

pub const DEFAULT_EXIT_WAIT_WINDOW: TimeDelta = TimeDelta { seconds: 3 * WEEK };
pub const MAX_EXIT_WAIT_WINDOW: TimeDelta = TimeDelta { seconds: 12 * WEEK };
pub const BASE_VALUE: Index = 10_000_000_000_000_000_000_000_000_000; // 10**28
pub const STRK_IN_FRIS: Amount = 1_000_000_000_000_000_000; // 10**18
pub const DEFAULT_C_NUM: Inflation = 160;
pub const MAX_C_NUM: Inflation = 500;
pub const C_DENOM: Inflation = 10_000;
pub const MIN_ATTESTATION_WINDOW: u16 = 11;
pub const STARTING_EPOCH: Epoch = 0;
pub const PREV_CONTRACT_VERSION: Version = '0';
