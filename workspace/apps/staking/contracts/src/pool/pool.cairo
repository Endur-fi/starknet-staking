#[starknet::contract]
pub mod Pool {
    use RolesComponent::InternalTrait as RolesInternalTrait;
    use core::num::traits::zero::Zero;
    use core::option::OptionTrait;
    use core::panics::panic_with_byte_array;
    use core::serde::Serde;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use staking::constants::FIRST_VALID_EPOCH;
    use staking::errors::GenericError;
    use staking::pool::errors::Error;
    use staking::pool::interface::{Events, IPool, IPoolMigration, PoolContractInfo, PoolMemberInfo};
    use staking::pool::objects::{
        InternalPoolMemberInfoConvertTrait, InternalPoolMemberInfoLatestTrait, SwitchPoolData,
        VInternalPoolMemberInfo, VInternalPoolMemberInfoTrait,
    };
    use staking::pool::pool_member_balance_trace::trace::{
        MutablePoolMemberBalanceTraceTrait, PoolMemberBalanceTrace, PoolMemberBalanceTraceTrait,
        PoolMemberBalanceTrait, PoolMemberCheckpoint, PoolMemberCheckpointTrait,
    };
    use staking::staking::interface::{
        IStakingDispatcher, IStakingDispatcherTrait, IStakingPoolDispatcher,
        IStakingPoolDispatcherTrait, StakerInfo, StakerInfoTrait,
    };
    use staking::types::{
        Amount, Commission, Epoch, Index, InternalPoolMemberInfoLatest, VecIndex, Version,
    };
    use staking::utils::{CheckedIERC20DispatcherTrait, compute_global_index_diff};
    use starknet::class_hash::ClassHash;
    use starknet::event::EventEmitter;
    use starknet::storage::{Map, StorageMapReadAccess, StoragePathEntry, StoragePointerReadAccess};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::errors::{Describable, OptionAuxTrait};
    use starkware_utils::interfaces::identity::Identity;
    use starkware_utils::trace::trace::{MutableTraceTrait, Trace, TraceTrait};
    use starkware_utils::types::time::time::{Time, Timestamp};
    pub const CONTRACT_IDENTITY: felt252 = 'Staking Delegation Pool';
    pub const CONTRACT_VERSION: felt252 = '1.0.0';

    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        replaceability: ReplaceabilityComponent::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        roles: RolesComponent::Storage,
        staker_address: ContractAddress,
        // Map pool member to their pool member info.
        pool_member_info: Map<ContractAddress, VInternalPoolMemberInfo>,
        // Stores the final global index of staking contract if the staker was active during the
        // upgrade to V1. If the staker was removed in V0, it retains the final staker index.
        final_staker_index: Option<Index>,
        // Dispatcher for the staking contract's pool functions.
        staking_pool_dispatcher: IStakingPoolDispatcher,
        // Dispatcher for the token contract.
        token_dispatcher: IERC20Dispatcher,
        // Deprecated commission field, was used in V0.
        // commission: Commission,
        // Map pool member to their epoch-balance info.
        pool_member_epoch_balance: Map<ContractAddress, PoolMemberBalanceTrace>,
        // Map version to class hash of the contract.
        prev_class_hash: Map<Version, ClassHash>,
        // Indicates whether the staker has been removed from the staking contract.
        staker_removed: bool,
        // Maintains a cumulative sum of pool_rewards/pool_balance per epoch for member rewards
        // calculation.
        // Updated whenever rewards are received from the staking contract.
        rewards_info: Trace,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ReplaceabilityEvent: ReplaceabilityComponent::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        RolesEvent: RolesComponent::Event,
        PoolMemberExitIntent: Events::PoolMemberExitIntent,
        PoolMemberBalanceChanged: Events::PoolMemberBalanceChanged,
        PoolMemberRewardAddressChanged: Events::PoolMemberRewardAddressChanged,
        StakerRemoved: Events::StakerRemoved,
        PoolMemberRewardClaimed: Events::PoolMemberRewardClaimed,
        DeletePoolMember: Events::DeletePoolMember,
        NewPoolMember: Events::NewPoolMember,
        SwitchDelegationPool: Events::SwitchDelegationPool,
        PoolMemberExitAction: Events::PoolMemberExitAction,
    }


    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        staker_address: ContractAddress,
        staking_contract: ContractAddress,
        token_address: ContractAddress,
        governance_admin: ContractAddress,
    ) {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(upgrade_delay: Zero::zero());
        self.staker_address.write(staker_address);
        self
            .staking_pool_dispatcher
            .write(IStakingPoolDispatcher { contract_address: staking_contract });
        self.token_dispatcher.write(IERC20Dispatcher { contract_address: token_address });
        self.staker_removed.write(false);
        self.rewards_info.deref().insert(key: self.get_current_epoch(), value: 0);
    }

    #[abi(embed_v0)]
    impl _Identity of Identity<ContractState> {
        fn identify(self: @ContractState) -> felt252 nopanic {
            CONTRACT_IDENTITY
        }

        fn version(self: @ContractState) -> felt252 nopanic {
            CONTRACT_VERSION
        }
    }

    #[abi(embed_v0)]
    impl PoolImpl of IPool<ContractState> {
        fn enter_delegation_pool(
            ref self: ContractState, reward_address: ContractAddress, amount: Amount,
        ) {
            // Asserts.
            self.assert_staker_is_active();
            let pool_member = get_caller_address();
            assert!(
                self.pool_member_info.read(pool_member).is_none(), "{}", Error::POOL_MEMBER_EXISTS,
            );
            assert!(amount.is_non_zero(), "{}", GenericError::AMOUNT_IS_ZERO);

            // Transfer funds from the delegator to the staking contract.
            let token_dispatcher = self.token_dispatcher.read();
            let staker_address = self.staker_address.read();
            self.transfer_from_delegator(:pool_member, :amount, :token_dispatcher);
            self.transfer_to_staking_contract(:amount, :token_dispatcher, :staker_address);

            // Create the pool member record.
            self
                .pool_member_info
                .write(
                    pool_member,
                    VInternalPoolMemberInfoTrait::new_latest(
                        reward_address: reward_address,
                        unpool_amount: Zero::zero(),
                        unpool_time: Option::None,
                        entry_to_claim_from: Zero::zero(),
                    ),
                );
            self.set_next_epoch_balance(:pool_member, :amount);

            // Emit events.
            self
                .emit(
                    Events::NewPoolMember { pool_member, staker_address, reward_address, amount },
                );
            self
                .emit(
                    Events::PoolMemberBalanceChanged {
                        pool_member, old_delegated_stake: Zero::zero(), new_delegated_stake: amount,
                    },
                );
        }

        fn add_to_delegation_pool(
            ref self: ContractState, pool_member: ContractAddress, amount: Amount,
        ) -> Amount {
            // Asserts.
            self.assert_staker_is_active();
            let mut pool_member_info = self.internal_pool_member_info(:pool_member);
            let caller_address = get_caller_address();
            assert!(
                caller_address == pool_member || caller_address == pool_member_info.reward_address,
                "{}",
                Error::CALLER_CANNOT_ADD_TO_POOL,
            );
            assert!(amount.is_non_zero(), "{}", GenericError::AMOUNT_IS_ZERO);

            // Transfer funds from the delegator to the staking contract.
            let token_dispatcher = self.token_dispatcher.read();
            let staker_address = self.staker_address.read();
            self.transfer_from_delegator(pool_member: caller_address, :amount, :token_dispatcher);
            self.transfer_to_staking_contract(:amount, :token_dispatcher, :staker_address);

            let old_delegated_stake = self.get_or_create_amount(:pool_member);

            // Update the pool member's balance checkpoint.
            self.increase_next_epoch_balance(:pool_member, :amount);
            let new_delegated_stake = old_delegated_stake + amount;

            // Emit events.
            self
                .emit(
                    Events::PoolMemberBalanceChanged {
                        pool_member, old_delegated_stake, new_delegated_stake,
                    },
                );

            new_delegated_stake
        }

        fn exit_delegation_pool_intent(ref self: ContractState, amount: Amount) {
            // Asserts.
            let pool_member = get_caller_address();
            let mut pool_member_info = self.internal_pool_member_info(:pool_member);
            let old_delegated_stake = self.get_or_create_amount(:pool_member);
            let total_amount = old_delegated_stake + pool_member_info.unpool_amount;
            assert!(amount <= total_amount, "{}", GenericError::AMOUNT_TOO_HIGH);

            // Notify the staking contract of the removal intent.
            let unpool_time = self.undelegate_from_staking_contract_intent(:pool_member, :amount);

            // Edit the pool member to reflect the removal intent, and write to storage.
            if amount.is_zero() {
                pool_member_info.unpool_time = Option::None;
            } else {
                pool_member_info.unpool_time = Option::Some(unpool_time);
            }
            pool_member_info.unpool_amount = amount;
            let new_delegated_stake = total_amount - amount;
            self
                .pool_member_info
                .write(pool_member, VInternalPoolMemberInfoTrait::wrap_latest(pool_member_info));

            // Update the pool member's balance checkpoint.
            self.set_next_epoch_balance(:pool_member, amount: new_delegated_stake);

            // Emit events.
            self
                .emit(
                    Events::PoolMemberExitIntent {
                        pool_member, exit_timestamp: unpool_time, amount,
                    },
                );
            self
                .emit(
                    Events::PoolMemberBalanceChanged {
                        pool_member, old_delegated_stake, new_delegated_stake,
                    },
                );
        }

        fn exit_delegation_pool_action(
            ref self: ContractState, pool_member: ContractAddress,
        ) -> Amount {
            // Asserts.
            let mut pool_member_info = self.internal_pool_member_info(:pool_member);
            let unpool_time = pool_member_info
                .unpool_time
                .expect_with_err(Error::MISSING_UNDELEGATE_INTENT);
            assert!(Time::now() >= unpool_time, "{}", GenericError::INTENT_WINDOW_NOT_FINISHED);

            // Emit event.
            self
                .emit(
                    Events::PoolMemberExitAction {
                        pool_member, unpool_amount: pool_member_info.unpool_amount,
                    },
                );

            // Perform removal action in the staking contract, receiving funds if needed.
            // Note that if the intent was done after the staker was removed (unstake_action),
            // the funds will already be in the pool contract, and the following call will do
            // nothing.
            let staking_pool_dispatcher = self.staking_pool_dispatcher.read();
            staking_pool_dispatcher
                .remove_from_delegation_pool_action(identifier: pool_member.into());

            // Transfer delegated amount to the pool member.
            let unpool_amount = pool_member_info.unpool_amount;
            pool_member_info.unpool_amount = Zero::zero();
            let token_dispatcher = self.token_dispatcher.read();
            token_dispatcher.checked_transfer(recipient: pool_member, amount: unpool_amount.into());

            // Write the updated pool member info to storage (remove if needed).
            if self.get_or_create_amount(:pool_member).is_zero() {
                // Transfer rewards to delegator's reward address.
                self.send_rewards_to_member(ref :pool_member_info, :pool_member, :token_dispatcher);
                self.remove_pool_member(:pool_member);
            } else {
                pool_member_info.unpool_time = Option::None;
                self
                    .pool_member_info
                    .write(
                        pool_member, VInternalPoolMemberInfoTrait::wrap_latest(pool_member_info),
                    );
            }

            unpool_amount
        }

        fn claim_rewards(ref self: ContractState, pool_member: ContractAddress) -> Amount {
            // Asserts.
            let mut pool_member_info = self.internal_pool_member_info(:pool_member);
            let caller_address = get_caller_address();
            let reward_address = pool_member_info.reward_address;
            assert!(
                caller_address == pool_member || caller_address == reward_address,
                "{}",
                Error::POOL_CLAIM_REWARDS_FROM_UNAUTHORIZED_ADDRESS,
            );

            self.insert_curr_epoch_balance(:pool_member);

            // Calculate rewards and update entry_to_claim_from.
            let (rewards, entry_to_claim_from) = self.calculate_rewards(:pool_member);
            // TODO: Change back to `unclaimed_rewards` or impl new
            // `send_rewards_to_member` function without `unclaimed_rewards` field.
            pool_member_info._deprecated_unclaimed_rewards += rewards;
            pool_member_info.entry_to_claim_from = entry_to_claim_from;

            // Transfer rewards to the pool member.
            let rewards = pool_member_info._deprecated_unclaimed_rewards;
            let token_dispatcher = self.token_dispatcher.read();
            self.send_rewards_to_member(ref :pool_member_info, :pool_member, :token_dispatcher);

            // Write the updated pool member info to storage.
            self
                .pool_member_info
                .write(pool_member, VInternalPoolMemberInfoTrait::wrap_latest(pool_member_info));

            rewards
        }

        fn switch_delegation_pool(
            ref self: ContractState,
            to_staker: ContractAddress,
            to_pool: ContractAddress,
            amount: Amount,
        ) -> Amount {
            // Asserts.
            assert!(amount.is_non_zero(), "{}", GenericError::AMOUNT_IS_ZERO);
            let pool_member = get_caller_address();
            let mut pool_member_info = self.internal_pool_member_info(:pool_member);
            assert!(pool_member_info.unpool_time.is_some(), "{}", Error::MISSING_UNDELEGATE_INTENT);
            assert!(amount <= pool_member_info.unpool_amount, "{}", GenericError::AMOUNT_TOO_HIGH);
            let reward_address = pool_member_info.reward_address;

            // Update pool_member_info and write to storage.
            pool_member_info.unpool_amount -= amount;
            if pool_member_info.unpool_amount.is_zero()
                && self.get_or_create_amount(:pool_member).is_zero() {
                // Both unpool_amount and amount are zero, send rewards and remove pool member.
                let token_dispatcher = self.token_dispatcher.read();
                self.send_rewards_to_member(ref :pool_member_info, :pool_member, :token_dispatcher);
                self.remove_pool_member(:pool_member);
            } else {
                // One of pool member unpool_amount or amount is non-zero.
                if pool_member_info.unpool_amount.is_zero() {
                    // unpool_amount is zero, clear unpool_time.
                    pool_member_info.unpool_time = Option::None;
                }
                self
                    .pool_member_info
                    .write(
                        pool_member, VInternalPoolMemberInfoTrait::wrap_latest(pool_member_info),
                    );
            }

            // Serialize the switch pool data and invoke the staking contract to switch pool.
            let switch_pool_data = SwitchPoolData { pool_member, reward_address };
            let mut serialized_data = array![];
            switch_pool_data.serialize(ref output: serialized_data);
            self
                .staking_pool_dispatcher
                .read()
                .switch_staking_delegation_pool(
                    :to_staker,
                    :to_pool,
                    switched_amount: amount,
                    data: serialized_data.span(),
                    identifier: pool_member.into(),
                );

            // Emit event.
            self
                .emit(
                    Events::SwitchDelegationPool {
                        pool_member, new_delegation_pool: to_pool, amount,
                    },
                );

            pool_member_info.unpool_amount
        }

        /// This function is called by the staking contract to enter the pool during a pool switch.
        fn enter_delegation_pool_from_staking_contract(
            ref self: ContractState, amount: Amount, data: Span<felt252>,
        ) {
            // Asserts.
            assert!(amount.is_non_zero(), "{}", GenericError::AMOUNT_IS_ZERO);
            self.assert_caller_is_staking_contract();

            // Deserialize the switch pool data.
            let mut serialized = data;
            let switch_pool_data: SwitchPoolData = Serde::deserialize(ref :serialized)
                .expect_with_err(Error::SWITCH_POOL_DATA_DESERIALIZATION_FAILED);
            let pool_member = switch_pool_data.pool_member;

            // Create or update the pool member info, depending on whether the pool member exists,
            // and then commit to storage.
            let pool_member_info = match self.get_internal_pool_member_info(:pool_member) {
                Option::Some(mut pool_member_info) => {
                    // Pool member already exists. Need to update pool_member_info to account for
                    // the accrued rewards and then update the delegated amount.
                    assert!(
                        pool_member_info.reward_address == switch_pool_data.reward_address,
                        "{}",
                        Error::REWARD_ADDRESS_MISMATCH,
                    );
                    // Update the pool member's balance checkpoint.
                    self.increase_next_epoch_balance(:pool_member, :amount);
                    pool_member_info
                },
                Option::None => {
                    // Pool member does not exist. Create a new record.
                    let reward_address = switch_pool_data.reward_address;
                    let pool_member_info = InternalPoolMemberInfoLatestTrait::new(:reward_address);

                    // Update the pool member's balance checkpoint.
                    self.set_next_epoch_balance(:pool_member, :amount);
                    let staker_address = self.staker_address.read();
                    self
                        .emit(
                            Events::NewPoolMember {
                                pool_member, staker_address, reward_address, amount,
                            },
                        );
                    pool_member_info
                },
            };
            self
                .pool_member_info
                .write(pool_member, VInternalPoolMemberInfoTrait::wrap_latest(pool_member_info));

            let new_delegated_stake = self.get_or_create_amount(:pool_member);

            // Emit event.
            self
                .emit(
                    Events::PoolMemberBalanceChanged {
                        pool_member,
                        old_delegated_stake: new_delegated_stake - amount,
                        new_delegated_stake,
                    },
                );
        }

        /// This function is called by the staking contract to notify the pool that the staker has
        /// been removed from the staking contract.
        fn set_staker_removed(ref self: ContractState) {
            // Asserts.
            self.assert_caller_is_staking_contract();
            assert!(!self.staker_removed.read(), "{}", Error::STAKER_ALREADY_REMOVED);
            self.staker_removed.write(true);
            // Emit event.
            self.emit(Events::StakerRemoved { staker_address: self.staker_address.read() });
        }

        fn change_reward_address(ref self: ContractState, reward_address: ContractAddress) {
            let pool_member = get_caller_address();
            let mut pool_member_info = self.internal_pool_member_info(:pool_member);
            let old_address = pool_member_info.reward_address;

            // Update reward_address and commit to storage.
            pool_member_info.reward_address = reward_address;
            self
                .pool_member_info
                .write(pool_member, VInternalPoolMemberInfoTrait::wrap_latest(pool_member_info));

            // Emit event.
            self
                .emit(
                    Events::PoolMemberRewardAddressChanged {
                        pool_member, new_address: reward_address, old_address,
                    },
                );
        }

        // This function provides the pool member info (with projected rewards).
        fn pool_member_info(self: @ContractState, pool_member: ContractAddress) -> PoolMemberInfo {
            let mut pool_member_info = self.internal_pool_member_info(:pool_member);

            let mut external_pool_member_info: PoolMemberInfo = pool_member_info.into();
            external_pool_member_info.amount = self.get_amount(:pool_member);
            let (rewards, _) = self.calculate_rewards(:pool_member);
            external_pool_member_info.unclaimed_rewards += rewards;
            external_pool_member_info.commission = self.get_commission_from_staking_contract();
            external_pool_member_info
        }

        fn get_pool_member_info(
            self: @ContractState, pool_member: ContractAddress,
        ) -> Option<PoolMemberInfo> {
            if self.pool_member_info.read(pool_member).is_none() {
                return Option::None;
            }
            Option::Some(self.pool_member_info(pool_member))
        }

        fn contract_parameters(self: @ContractState) -> PoolContractInfo {
            PoolContractInfo {
                staker_address: self.staker_address.read(),
                final_staker_index: self.final_staker_index.read(),
                staking_contract: self.staking_pool_dispatcher.read().contract_address,
                token_address: self.token_dispatcher.read().contract_address,
                commission: self.get_commission_from_staking_contract(),
                staker_removed: self.staker_removed.read(),
            }
        }

        /// **Note:** This function is not tested yet.
        fn update_rewards_from_staking_contract(
            ref self: ContractState, rewards: Amount, pool_balance: Amount,
        ) {
            self.assert_caller_is_staking_contract();
            let latest = match self.rewards_info.deref().latest() {
                Result::Ok((_, latest)) => latest,
                Result::Err(_) => 0,
            };
            self
                .rewards_info
                .deref()
                .insert(
                    key: self.get_current_epoch(),
                    value: latest
                        + compute_global_index_diff(
                            staking_rewards: rewards, total_stake: pool_balance,
                        ),
                );
            // TODO: emit event.
        }
    }

    #[abi(embed_v0)]
    impl PoolMigrationImpl of IPoolMigration<ContractState> {
        fn internal_pool_member_info(
            self: @ContractState, pool_member: ContractAddress,
        ) -> InternalPoolMemberInfoLatest {
            let v_internal_pool_member_info = self.pool_member_info.read(pool_member);
            match v_internal_pool_member_info {
                VInternalPoolMemberInfo::None => panic_with_byte_array(
                    err: @Error::POOL_MEMBER_DOES_NOT_EXIST.describe(),
                ),
                VInternalPoolMemberInfo::V0(info_v0) => info_v0
                    .convert(self.get_prev_class_hash(), pool_member),
                VInternalPoolMemberInfo::V1(info_v1) => info_v1,
            }
        }

        fn get_internal_pool_member_info(
            self: @ContractState, pool_member: ContractAddress,
        ) -> Option<InternalPoolMemberInfoLatest> {
            let v_internal_pool_member_info = self.pool_member_info.read(pool_member);
            match v_internal_pool_member_info {
                VInternalPoolMemberInfo::None => Option::None,
                _ => Option::Some(self.internal_pool_member_info(:pool_member)),
            }
        }
    }

    #[generate_trait]
    pub(crate) impl InternalPoolMigration of IPoolMigrationInternal {
        /// Returns the class hash of the previous contract version.
        ///
        /// **Note**: This function must be reimplemented in the next version of the contract.
        fn get_prev_class_hash(self: @ContractState) -> ClassHash {
            self.prev_class_hash.read(0)
        }
    }

    #[generate_trait]
    pub(crate) impl InternalPoolFunctions of InternalPoolFunctionsTrait {
        fn remove_pool_member(ref self: ContractState, pool_member: ContractAddress) {
            let reward_address = self.internal_pool_member_info(:pool_member).reward_address;
            self.pool_member_info.write(pool_member, VInternalPoolMemberInfo::None);
            self.emit(Events::DeletePoolMember { pool_member, reward_address });
        }

        fn assert_staker_is_active(self: @ContractState) {
            assert!(self.is_staker_active(), "{}", Error::STAKER_INACTIVE);
        }

        fn is_staker_active(self: @ContractState) -> bool {
            !self.staker_removed.read()
        }

        fn undelegate_from_staking_contract_intent(
            self: @ContractState, pool_member: ContractAddress, amount: Amount,
        ) -> Timestamp {
            if !self.is_staker_active() {
                // Don't allow intent if an intent is already in progress and the staker is erased.
                assert!(
                    self.internal_pool_member_info(:pool_member).unpool_time.is_none(),
                    "{}",
                    Error::UNDELEGATE_IN_PROGRESS,
                );
                return Time::now();
            }
            let staking_pool_dispatcher = self.staking_pool_dispatcher.read();
            let staker_address = self.staker_address.read();
            staking_pool_dispatcher
                .remove_from_delegation_pool_intent(
                    :staker_address, identifier: pool_member.into(), :amount,
                )
        }

        /// Sends the rewards to the `pool_member`'s reward address, and zeroes unclaimed_rewards.
        /// Important note:
        /// After calling this function, one must write the updated pool_member_info to the storage.
        fn send_rewards_to_member(
            ref self: ContractState,
            ref pool_member_info: InternalPoolMemberInfoLatest,
            pool_member: ContractAddress,
            token_dispatcher: IERC20Dispatcher,
        ) {
            let reward_address = pool_member_info.reward_address;
            let amount = pool_member_info._deprecated_unclaimed_rewards;

            token_dispatcher.checked_transfer(recipient: reward_address, amount: amount.into());
            pool_member_info._deprecated_unclaimed_rewards = Zero::zero();

            // TODO: update entry_to_claim_from of pool member info.

            self.emit(Events::PoolMemberRewardClaimed { pool_member, reward_address, amount });
        }

        fn staker_info(self: @ContractState) -> StakerInfo {
            let contract_address = self.staking_pool_dispatcher.read().contract_address;
            let staking_dispatcher = IStakingDispatcher { contract_address };
            staking_dispatcher.staker_info(staker_address: self.staker_address.read())
        }

        /// Transfer funds of the specified amount from the given delegator to the pool.
        ///
        /// Sufficient approvals of transfer is a pre-condition.
        fn transfer_from_delegator(
            self: @ContractState,
            pool_member: ContractAddress,
            amount: Amount,
            token_dispatcher: IERC20Dispatcher,
        ) {
            let self_contract = get_contract_address();
            token_dispatcher
                .checked_transfer_from(
                    sender: pool_member, recipient: self_contract, amount: amount.into(),
                );
        }

        /// Transfer funds of the specified amount from the pool to the staking contract.
        ///
        /// Approve the transfer and notify staking contract of the new delegated stake.
        fn transfer_to_staking_contract(
            self: @ContractState,
            amount: Amount,
            token_dispatcher: IERC20Dispatcher,
            staker_address: ContractAddress,
        ) {
            // Approve staking contract to transfer funds from the pool.
            let staking_pool_dispatcher = self.staking_pool_dispatcher.read();
            token_dispatcher
                .approve(spender: staking_pool_dispatcher.contract_address, amount: amount.into());

            // Notify the staking contract of the new delegated stake.
            // This will complete the fund transfer to the staking contract.
            staking_pool_dispatcher.add_stake_from_pool(:staker_address, :amount);
        }

        fn assert_caller_is_staking_contract(self: @ContractState) {
            assert!(
                get_caller_address() == self.staking_pool_dispatcher.read().contract_address,
                "{}",
                GenericError::CALLER_IS_NOT_STAKING_CONTRACT,
            );
        }

        fn get_current_epoch(self: @ContractState) -> Epoch {
            let staking_dispatcher = IStakingDispatcher {
                contract_address: self.staking_pool_dispatcher.read().contract_address,
            };
            staking_dispatcher.get_current_epoch()
        }

        fn get_next_epoch(self: @ContractState) -> Epoch {
            self.get_current_epoch() + 1
        }

        fn get_amount(self: @ContractState, pool_member: ContractAddress) -> Amount {
            // After upgrading to V1, `pool_member_epoch_balance` remains uninitialized
            // until the pool member's balance is modified for the first time. If initialized,
            // return the `amount` recorded in the trace, which reflects the latest delegated
            // amount.
            // Otherwise, return `pool_member_info.amount`.
            let trace = self.pool_member_epoch_balance.entry(key: pool_member);
            if trace.is_initialized() {
                let (_, pool_member_balance) = trace.latest();
                pool_member_balance.balance()
            } else {
                self.internal_pool_member_info(:pool_member)._deprecated_amount
            }
        }

        fn get_or_create_amount(ref self: ContractState, pool_member: ContractAddress) -> Amount {
            // Return the `amount` recorded in the `pool_member_epoch_balance` trace.
            // If it is uninitialized, initialize it to `pool_member_info._deprecated_amount`.
            let trace = self.pool_member_epoch_balance.entry(key: pool_member);
            if trace.is_initialized() {
                let (_, pool_member_balance) = trace.latest();
                pool_member_balance.balance()
            } else {
                let balance = self.internal_pool_member_info(:pool_member)._deprecated_amount;
                trace
                    .insert(
                        key: FIRST_VALID_EPOCH,
                        value: PoolMemberBalanceTrait::new(:balance, rewards_info_idx: 0),
                    );
                balance
            }
        }

        fn set_next_epoch_balance(
            ref self: ContractState, pool_member: ContractAddress, amount: Amount,
        ) {
            let member_checkpoint = self.pool_member_epoch_balance.entry(pool_member);
            let pool_member_balance = PoolMemberBalanceTrait::new(
                balance: amount, rewards_info_idx: self.rewards_info_length(),
            );
            member_checkpoint.insert(key: self.get_next_epoch(), value: pool_member_balance);
            // TODO: Emit event?
        }

        fn increase_next_epoch_balance(
            ref self: ContractState, pool_member: ContractAddress, amount: Amount,
        ) {
            let current_balance = self.get_or_create_amount(:pool_member);
            let pool_member_balance = PoolMemberBalanceTrait::new(
                balance: current_balance + amount, rewards_info_idx: self.rewards_info_length(),
            );
            self
                .pool_member_epoch_balance
                .entry(pool_member)
                .insert(key: self.get_next_epoch(), value: pool_member_balance);
            // TODO: Emit event?
        }

        /// Inserts the current epoch into the trace if it is missing.
        /// The current epoch's entry will be the entry_to_claim_from for the next claim.
        ///
        /// This function is called when claiming rewards.
        fn insert_curr_epoch_balance(ref self: ContractState, pool_member: ContractAddress) {
            let current_balance = self.get_or_create_amount(:pool_member);
            let trace = self.pool_member_epoch_balance.entry(pool_member);
            let (latest_epoch, _) = trace.latest();
            let current_epoch = self.get_current_epoch();
            if latest_epoch <= current_epoch {
                trace
                    .insert(
                        key: current_epoch,
                        value: PoolMemberBalanceTrait::new(
                            balance: current_balance,
                            rewards_info_idx: self.rewards_info_length() - 1,
                        ),
                    );
            } else {
                trace
                    .insert_before_latest(
                        key: current_epoch, rewards_info_idx: self.rewards_info_length() - 1,
                    );
            }
            // TODO: Emit event?
        }

        fn rewards_info_length(self: @ContractState) -> VecIndex {
            self.rewards_info.deref().length()
        }

        /// TODO: Implement.
        fn calculate_rewards(
            self: @ContractState, pool_member: ContractAddress,
        ) -> (Amount, VecIndex) {
            (Zero::zero(), Zero::zero())
        }

        /// Find the latest rewards aggregated sum (a.k.a sigma) before the change in staking
        /// power listed in the provided pool member checkpoint.
        fn find_sigma(
            self: @ContractState, pool_member_checkpoint: PoolMemberCheckpoint,
        ) -> Amount {
            let rewards_info_vec = self.rewards_info.deref();
            let rewards_info_idx = pool_member_checkpoint.rewards_info_idx();

            // Pool member enter delegation before any rewards given to the pool.
            if rewards_info_idx == 0 {
                return Zero::zero();
            }

            // Next rewards idx was written, and no rewards given to pool from that moment.
            if rewards_info_vec.length() == rewards_info_idx {
                let (_, sigma) = rewards_info_vec.at(rewards_info_idx - 1);
                return sigma;
            }

            // Pool member changed balance in epoch j, so j+1 written to pool member checkpoint.
            let (epoch_at_index, sigma_at_index) = rewards_info_vec.at(rewards_info_idx);
            if pool_member_checkpoint.epoch() > epoch_at_index {
                // If pool rewards for epoch j given after pool member balance changed, then pool
                // member is not eligible in this `reward_info_idx` and it is infact the latest one
                // before the staking power change.
                assert!(
                    epoch_at_index == pool_member_checkpoint.epoch() - 1,
                    "{}",
                    Error::UNEXPECTED_EPOCH,
                );
                sigma_at_index
            } else {
                // Else, the pool rewards index given is for an epoch bigger than j, meaning pool
                // member is eligible for sigma at `rewards_info_idx` and we should take the
                // previous entry.
                let (_, sigma_at_index_minus_one) = rewards_info_vec.at(rewards_info_idx - 1);
                sigma_at_index_minus_one
            }
        }

        fn get_commission_from_staking_contract(self: @ContractState) -> Commission {
            if self.staker_removed.read() {
                return Zero::zero();
            }
            let staking_dispatcher = IStakingDispatcher {
                contract_address: self.staking_pool_dispatcher.read().contract_address,
            };
            staking_dispatcher
                .staker_info(staker_address: self.staker_address.read())
                .get_pool_info()
                .commission
        }
    }
}
