use core::cmp::max;
use core::num::traits::Zero;
use staking::staking::errors::Error;
use staking::staking::interface::{
    IStakingDispatcherTrait, IStakingLibraryDispatcher, StakerInfo, StakerPoolInfo,
};
use staking::types::{Amount, Epoch, Index, InternalStakerInfoLatest};
use starknet::{ClassHash, ContractAddress, get_block_number};
use starkware_utils::errors::OptionAuxTrait;
use starkware_utils::types::time::time::{Time, TimeDelta, Timestamp};

const SECONDS_IN_YEAR: u64 = 365 * 24 * 60 * 60;

#[derive(Hash, Drop, Serde, Copy, starknet::Store)]
pub(crate) struct UndelegateIntentKey {
    pub pool_contract: ContractAddress,
    // The identifier is generally the pool member address, but it can be any unique identifier,
    // depending on the logic of the pool contract.
    pub identifier: felt252,
}

#[derive(Debug, PartialEq, Drop, Serde, Copy, starknet::Store)]
pub(crate) struct UndelegateIntentValue {
    pub unpool_time: Timestamp,
    pub amount: Amount,
}

pub(crate) impl UndelegateIntentValueZero of core::num::traits::Zero<UndelegateIntentValue> {
    fn zero() -> UndelegateIntentValue {
        UndelegateIntentValue { unpool_time: Zero::zero(), amount: Zero::zero() }
    }

    fn is_zero(self: @UndelegateIntentValue) -> bool {
        *self == Self::zero()
    }

    fn is_non_zero(self: @UndelegateIntentValue) -> bool {
        !self.is_zero()
    }
}

#[generate_trait]
pub(crate) impl UndelegateIntentValueImpl of UndelegateIntentValueTrait {
    fn is_valid(self: @UndelegateIntentValue) -> bool {
        // The value is valid if and only if unpool_time and amount are both zero or both non-zero.
        self.unpool_time.is_zero() == self.amount.is_zero()
    }

    fn assert_valid(self: @UndelegateIntentValue) {
        assert!(self.is_valid(), "{}", Error::INVALID_UNDELEGATE_INTENT_VALUE);
    }
}

// TODO: pack
#[derive(Debug, Hash, Drop, Serde, Copy, PartialEq, starknet::Store)]
pub(crate) struct EpochInfo {
    // The duration of a block in seconds.
    block_duration: u16,
    // The length of the epoch in blocks.
    length: u16,
    // The first block of the first epoch with this length.
    starting_block: u64,
    // The first epoch id with this length, changes by a call to update.
    starting_epoch: Epoch,
    // The last starting block of the last epoch with previous length.
    last_starting_block_before_update: u64,
}

#[generate_trait]
pub(crate) impl EpochInfoImpl of EpochInfoTrait {
    fn new(block_duration: u16, epoch_length: u16, starting_block: u64) -> EpochInfo {
        assert!(epoch_length.is_non_zero(), "{}", Error::INVALID_EPOCH_LENGTH);
        assert!(block_duration.is_non_zero(), "{}", Error::INVALID_BLOCK_DURATION);
        EpochInfo {
            block_duration,
            length: epoch_length,
            starting_block,
            starting_epoch: Zero::zero(),
            last_starting_block_before_update: Zero::zero(),
        }
    }

    fn current_epoch(self: @EpochInfo) -> Epoch {
        let current_block = get_block_number();
        // If the epoch info updated and the current block is before the starting block of the
        // next epoch with the new length.
        if current_block < *self.starting_block {
            return *self.starting_epoch - 1;
        }
        ((current_block - *self.starting_block) / self.epoch_len_in_blocks().into())
            + *self.starting_epoch
    }

    fn update(ref self: EpochInfo, block_duration: u16, epoch_length: u16) {
        assert!(epoch_length.is_non_zero(), "{}", Error::INVALID_EPOCH_LENGTH);
        assert!(block_duration.is_non_zero(), "{}", Error::INVALID_BLOCK_DURATION);
        self.last_starting_block_before_update = self.current_epoch_starting_block();
        self.starting_epoch = self.next_epoch();
        self.starting_block = self.calculate_next_epoch_starting_block();
        self.length = epoch_length;
        self.block_duration = block_duration;
    }

    fn epochs_in_year(self: @EpochInfo) -> u64 {
        let blocks_in_year = SECONDS_IN_YEAR / (*self.block_duration).into();
        blocks_in_year / self.epoch_len_in_blocks().into()
    }

    fn epoch_len_in_blocks(self: @EpochInfo) -> u16 {
        if *self.starting_block > get_block_number() {
            // There was an update in this epoch, so we need to compute the previous length.
            (*self.starting_block - *self.last_starting_block_before_update).try_into().unwrap()
        } else {
            // No update in this epoch, so we can return the length.
            *self.length
        }
    }

    fn current_epoch_starting_block(self: @EpochInfo) -> u64 {
        if *self.starting_block > get_block_number() {
            // The epoch info updated and the current block is before the starting block of the
            // next epoch with the new length.
            return *self.last_starting_block_before_update;
        }
        self.calculate_next_epoch_starting_block() - self.epoch_len_in_blocks().into()
    }
}

#[generate_trait]
impl PrivateEpochInfoImpl of PrivateEpochInfoTrait {
    fn calculate_next_epoch_starting_block(self: @EpochInfo) -> u64 {
        let current_block = get_block_number();
        let blocks_passed = current_block - *self.starting_block;
        let length: u64 = self.epoch_len_in_blocks().into();
        let blocks_to_next_epoch = length - (blocks_passed % length);
        current_block + blocks_to_next_epoch
    }

    fn next_epoch(self: @EpochInfo) -> Epoch {
        self.current_epoch() + 1
    }
}

#[derive(Debug, PartialEq, Drop, Serde, Copy, starknet::Store)]
struct InternalStakerInfo {
    reward_address: ContractAddress,
    operational_address: ContractAddress,
    unstake_time: Option<Timestamp>,
    amount_own: Amount,
    index: Index,
    unclaimed_rewards_own: Amount,
    pool_info: Option<StakerPoolInfo>,
}

// **Note**: This struct should be made private in the next version of Internal Staker Info.
#[derive(Debug, PartialEq, Drop, Serde, Copy, starknet::Store)]
pub(crate) struct InternalStakerInfoV1 {
    pub(crate) reward_address: ContractAddress,
    pub(crate) operational_address: ContractAddress,
    pub(crate) unstake_time: Option<Timestamp>,
    // **Note**: This field was used in V0 and is replaced by `staker_balance_trace` in V1.
    pub(crate) _deprecated_amount_own: Amount,
    // **Note**: This field was used in V0 and no longer in use in the new rewards mechanism
    // introduced in V1.
    pub(crate) _deprecated_index: Index,
    pub(crate) unclaimed_rewards_own: Amount,
    pub(crate) pool_info: Option<StakerPoolInfo>,
}

// **Note**: This struct should be updated in the next version of Internal Staker Info.
#[derive(Debug, PartialEq, Serde, Drop, Copy, starknet::Store)]
pub(crate) enum VersionedInternalStakerInfo {
    V0: InternalStakerInfo,
    #[default]
    None,
    V1: InternalStakerInfoV1,
}

// **Note**: This trait must be reimplemented in the next version of Internal Staker Info.
#[generate_trait]
pub(crate) impl InternalStakerInfoConvert of InternalStakerInfoConvertTrait {
    fn convert(
        self: InternalStakerInfo, prev_class_hash: ClassHash, staker_address: ContractAddress,
    ) -> InternalStakerInfoV1 {
        let library_dispatcher = IStakingLibraryDispatcher { class_hash: prev_class_hash };
        library_dispatcher.staker_info(staker_address).into()
    }
}

// **Note**: This trait must be reimplemented in the next version of Internal Staker Info.
#[generate_trait]
pub(crate) impl VersionedInternalStakerInfoImpl of VersionedInternalStakerInfoTrait {
    fn wrap_latest(value: InternalStakerInfoV1) -> VersionedInternalStakerInfo nopanic {
        VersionedInternalStakerInfo::V1(value)
    }

    fn new_latest(
        reward_address: ContractAddress,
        operational_address: ContractAddress,
        unstake_time: Option<Timestamp>,
        amount_own: Amount,
        unclaimed_rewards_own: Amount,
        pool_info: Option<StakerPoolInfo>,
    ) -> VersionedInternalStakerInfo {
        VersionedInternalStakerInfo::V1(
            InternalStakerInfoV1 {
                reward_address,
                operational_address,
                unstake_time,
                _deprecated_amount_own: amount_own,
                _deprecated_index: Zero::zero(),
                unclaimed_rewards_own,
                pool_info,
            },
        )
    }

    fn is_none(self: @VersionedInternalStakerInfo) -> bool nopanic {
        match *self {
            VersionedInternalStakerInfo::None => true,
            _ => false,
        }
    }
}

#[generate_trait]
pub(crate) impl InternalStakerInfoLatestImpl of InternalStakerInfoLatestTrait {
    fn compute_unpool_time(
        self: @InternalStakerInfoLatest, exit_wait_window: TimeDelta,
    ) -> Timestamp {
        if let Option::Some(unstake_time) = *self.unstake_time {
            return max(unstake_time, Time::now());
        }
        Time::now().add(delta: exit_wait_window)
    }

    fn get_pool_info(self: @InternalStakerInfoLatest) -> StakerPoolInfo {
        (*self.pool_info).expect_with_err(Error::MISSING_POOL_CONTRACT)
    }

    fn get_total_amount(self: @InternalStakerInfoLatest) -> Amount {
        if let Option::Some(pool_info) = *self.pool_info {
            return pool_info.amount + *self._deprecated_amount_own;
        }
        (*self._deprecated_amount_own)
    }
}

impl InternalStakerInfoLatestIntoStakerInfo of Into<InternalStakerInfoLatest, StakerInfo> {
    fn into(self: InternalStakerInfoLatest) -> StakerInfo {
        StakerInfo {
            reward_address: self.reward_address,
            operational_address: self.operational_address,
            unstake_time: self.unstake_time,
            amount_own: self._deprecated_amount_own,
            index: Zero::zero(),
            unclaimed_rewards_own: self.unclaimed_rewards_own,
            pool_info: self.pool_info,
        }
    }
}

#[cfg(test)]
#[generate_trait]
pub(crate) impl VersionedInternalStakerInfoTestImpl of VersionedInternalStakerInfoTestTrait {
    fn new_v0(
        reward_address: ContractAddress,
        operational_address: ContractAddress,
        unstake_time: Option<Timestamp>,
        amount_own: Amount,
        index: Index,
        unclaimed_rewards_own: Amount,
        pool_info: Option<StakerPoolInfo>,
    ) -> VersionedInternalStakerInfo {
        VersionedInternalStakerInfo::V0(
            InternalStakerInfo {
                reward_address,
                operational_address,
                unstake_time,
                amount_own,
                index,
                unclaimed_rewards_own,
                pool_info,
            },
        )
    }
}

#[cfg(test)]
#[generate_trait]
pub(crate) impl InternalStakerInfoTestImpl of InternalStakerInfoTestTrait {
    fn new(
        reward_address: ContractAddress,
        operational_address: ContractAddress,
        unstake_time: Option<Timestamp>,
        amount_own: Amount,
        index: Index,
        unclaimed_rewards_own: Amount,
        pool_info: Option<StakerPoolInfo>,
    ) -> InternalStakerInfo {
        InternalStakerInfo {
            reward_address,
            operational_address,
            unstake_time,
            amount_own,
            index,
            unclaimed_rewards_own,
            pool_info,
        }
    }
}

/// This module is used in tests to verify that changing the storage type from
/// `Option<InternalStakerInfo>` to `VersionedInternalStakerInfo` retains the same `StoragePath`
/// and `StoragePtr`.
///
/// The `#[rename("staker_info")]` attribute ensures the variable name remains consistent,
/// as it is part of the storage path calculation.
#[cfg(test)]
#[starknet::contract]
pub mod VersionedStorageContractTest {
    use starknet::storage::Map;
    use super::{ContractAddress, InternalStakerInfo, VersionedInternalStakerInfo};

    #[storage]
    pub struct Storage {
        #[allow(starknet::colliding_storage_paths)]
        pub staker_info: Map<ContractAddress, Option<InternalStakerInfo>>,
        #[rename("staker_info")]
        pub new_staker_info: Map<ContractAddress, VersionedInternalStakerInfo>,
    }
}

#[derive(Serde, Drop, Copy, Debug)]
pub struct AttestationInfo {
    staker_address: ContractAddress,
    stake: Amount,
    epoch_len: u16,
    epoch_id: Epoch,
    current_epoch_starting_block: u64,
}

#[generate_trait]
pub impl AttestationInfoImpl of AttestationInfoTrait {
    fn new(
        staker_address: ContractAddress,
        stake: Amount,
        epoch_len: u16,
        epoch_id: Epoch,
        current_epoch_starting_block: u64,
    ) -> AttestationInfo {
        AttestationInfo { staker_address, stake, epoch_len, epoch_id, current_epoch_starting_block }
    }

    fn staker_address(self: AttestationInfo) -> ContractAddress {
        self.staker_address
    }
    fn stake(self: AttestationInfo) -> Amount {
        self.stake
    }
    fn epoch_len(self: AttestationInfo) -> u16 {
        self.epoch_len
    }
    fn epoch_id(self: AttestationInfo) -> Epoch {
        self.epoch_id
    }
    fn current_epoch_starting_block(self: AttestationInfo) -> u64 {
        self.current_epoch_starting_block
    }
    fn get_next_epoch_attestation_info(self: AttestationInfo) -> AttestationInfo {
        Self::new(
            staker_address: self.staker_address,
            stake: self.stake,
            epoch_len: self.epoch_len,
            epoch_id: self.epoch_id + 1,
            current_epoch_starting_block: self.current_epoch_starting_block + self.epoch_len.into(),
        )
    }
}
