#[starknet::contract]
pub mod Pool {
    use core::serde::Serde;
    use core::num::traits::zero::Zero;
    use contracts::errors::{Error, assert_with_err, OptionAuxTrait};
    use contracts::pool::{interface::PoolContractInfo, IPool, Events};
    use contracts::pool::{InternalPoolMemberInfo, PoolMemberInfo};
    use contracts::utils::{compute_rewards_rounded_down, compute_commission_amount_rounded_up};
    use core::option::OptionTrait;
    use starknet::{ContractAddress, get_caller_address, get_contract_address, get_block_timestamp};
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::interface::{IERC20DispatcherTrait, IERC20Dispatcher};
    use contracts::staking::interface::{IStakingPoolDispatcher, IStakingPoolDispatcherTrait};
    use starknet::storage::Map;
    use contracts_commons::components::roles::RolesComponent;
    use RolesComponent::InternalTrait as RolesInternalTrait;
    use contracts_commons::components::replaceability::ReplaceabilityComponent;
    use AccessControlComponent::InternalTrait as AccessControlInternalTrait;
    use contracts::utils::CheckedIERC20DispatcherTrait;
    use contracts::types::{Commission, TimeStamp, Index, Amount};

    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    #[derive(Debug, Drop, Serde, Copy)]
    pub struct SwitchPoolData {
        pub pool_member: ContractAddress,
        pub reward_address: ContractAddress,
    }

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
        pool_member_info: Map<ContractAddress, Option<InternalPoolMemberInfo>>,
        final_staker_index: Option<Index>,
        staking_pool_dispatcher: IStakingPoolDispatcher,
        erc20_dispatcher: IERC20Dispatcher,
        commission: Commission,
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
        FinalIndexSet: Events::FinalIndexSet,
        PoolMemberRewardClaimed: Events::PoolMemberRewardClaimed,
        DeletePoolMember: Events::DeletePoolMember,
        NewPoolMember: Events::NewPoolMember,
    }


    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        staker_address: ContractAddress,
        staking_contract: ContractAddress,
        token_address: ContractAddress,
        commission: Commission
    ) {
        self.accesscontrol.initializer();
        self.roles.initializer(governance_admin: staking_contract);
        self.replaceability.upgrade_delay.write(Zero::zero());
        self.staker_address.write(staker_address);
        self
            .staking_pool_dispatcher
            .write(IStakingPoolDispatcher { contract_address: staking_contract });
        self.erc20_dispatcher.write(IERC20Dispatcher { contract_address: token_address });
        self.commission.write(commission);
    }

    #[abi(embed_v0)]
    impl PoolImpl of IPool<ContractState> {
        fn enter_delegation_pool(
            ref self: ContractState, reward_address: ContractAddress, amount: Amount
        ) {
            self.assert_staker_is_active();
            let pool_member = get_caller_address();
            assert_with_err(
                self.pool_member_info.read(pool_member).is_none(), Error::POOL_MEMBER_EXISTS
            );
            assert_with_err(amount.is_non_zero(), Error::AMOUNT_IS_ZERO);
            let erc20_dispatcher = self.erc20_dispatcher.read();
            let self_contract = get_contract_address();
            erc20_dispatcher
                .checked_transfer_from(
                    sender: pool_member, recipient: self_contract, amount: amount.into()
                );
            let staking_pool_dispatcher = self.staking_pool_dispatcher.read();
            erc20_dispatcher
                .approve(spender: staking_pool_dispatcher.contract_address, amount: amount.into());
            let staker_address = self.staker_address.read();
            let updated_index = staking_pool_dispatcher
                .add_stake_from_pool(:staker_address, :amount);
            self
                .pool_member_info
                .write(
                    pool_member,
                    Option::Some(
                        InternalPoolMemberInfo {
                            reward_address: reward_address,
                            amount: amount,
                            index: updated_index,
                            unclaimed_rewards: Zero::zero(),
                            commission: self.commission.read(),
                            unpool_time: Option::None,
                            unpool_amount: Zero::zero(),
                        }
                    )
                );
            self
                .emit(
                    Events::NewPoolMember { pool_member, staker_address, reward_address, amount }
                );
            self
                .emit(
                    Events::PoolMemberBalanceChanged {
                        pool_member, old_delegated_stake: Zero::zero(), new_delegated_stake: amount
                    }
                );
        }

        fn add_to_delegation_pool(
            ref self: ContractState, pool_member: ContractAddress, amount: Amount
        ) -> Amount {
            self.assert_staker_is_active();
            let mut pool_member_info = self.get_pool_member_info(:pool_member);
            let caller_address = get_caller_address();
            assert_with_err(
                caller_address == pool_member || caller_address == pool_member_info.reward_address,
                Error::CALLER_CANNOT_ADD_TO_POOL
            );
            let erc20_dispatcher = self.erc20_dispatcher.read();
            let self_contract = get_contract_address();
            erc20_dispatcher
                .checked_transfer_from(
                    sender: caller_address, recipient: self_contract, amount: amount.into()
                );
            let staking_pool_dispatcher = self.staking_pool_dispatcher.read();
            erc20_dispatcher
                .approve(spender: staking_pool_dispatcher.contract_address, amount: amount.into());
            let updated_index = staking_pool_dispatcher
                .add_stake_from_pool(staker_address: self.staker_address.read(), :amount);
            self.update_rewards(ref :pool_member_info, :updated_index);
            let old_delegated_stake = pool_member_info.amount;
            pool_member_info.amount += amount;
            self.pool_member_info.write(pool_member, Option::Some(pool_member_info));
            self
                .emit(
                    Events::PoolMemberBalanceChanged {
                        pool_member,
                        old_delegated_stake,
                        new_delegated_stake: pool_member_info.amount
                    }
                );
            pool_member_info.amount
        }

        fn exit_delegation_pool_intent(ref self: ContractState, amount: Amount) {
            let pool_member = get_caller_address();
            let mut pool_member_info = self.get_pool_member_info(:pool_member);
            let total_amount = pool_member_info.amount + pool_member_info.unpool_amount;
            assert_with_err(amount <= total_amount, Error::AMOUNT_TOO_HIGH);
            let old_delegated_stake = pool_member_info.amount;
            self.update_index_and_update_rewards(ref :pool_member_info);
            let unpool_time = self.undelegate_from_staking_contract_intent(:pool_member, :amount);
            if amount.is_zero() {
                pool_member_info.unpool_time = Option::None;
            } else {
                pool_member_info.unpool_time = Option::Some(unpool_time);
            }
            pool_member_info.unpool_amount = amount;
            pool_member_info.amount = total_amount - amount;
            self.pool_member_info.write(pool_member, Option::Some(pool_member_info));
            self
                .emit(
                    Events::PoolMemberExitIntent {
                        pool_member, exit_timestamp: unpool_time, amount
                    }
                );
            self
                .emit(
                    Events::PoolMemberBalanceChanged {
                        pool_member,
                        old_delegated_stake,
                        new_delegated_stake: pool_member_info.amount
                    }
                );
        }

        fn exit_delegation_pool_action(
            ref self: ContractState, pool_member: ContractAddress
        ) -> Amount {
            let mut pool_member_info = self.get_pool_member_info(:pool_member);
            let unpool_time = pool_member_info
                .unpool_time
                .expect_with_err(Error::MISSING_UNDELEGATE_INTENT);
            assert_with_err(
                get_block_timestamp() >= unpool_time, Error::INTENT_WINDOW_NOT_FINISHED
            );
            // Clear intent and receive funds from staking contract if needed.
            let staking_pool_dispatcher = self.staking_pool_dispatcher.read();
            staking_pool_dispatcher
                .remove_from_delegation_pool_action(identifier: pool_member.into());

            let erc20_dispatcher = self.erc20_dispatcher.read();
            // Claim rewards.
            self.send_rewards_to_member(ref :pool_member_info, :pool_member, :erc20_dispatcher);
            // Transfer delegated amount to the pool member.
            let unpool_amount = pool_member_info.unpool_amount;
            pool_member_info.unpool_amount = Zero::zero();
            erc20_dispatcher.checked_transfer(recipient: pool_member, amount: unpool_amount.into());
            if pool_member_info.amount.is_zero() {
                self.remove_pool_member(:pool_member);
            } else {
                pool_member_info.unpool_time = Option::None;
                self.pool_member_info.write(pool_member, Option::Some(pool_member_info));
            }
            unpool_amount
        }

        fn claim_rewards(ref self: ContractState, pool_member: ContractAddress) -> Amount {
            let mut pool_member_info = self.get_pool_member_info(:pool_member);
            let caller_address = get_caller_address();
            let reward_address = pool_member_info.reward_address;
            assert_with_err(
                caller_address == pool_member || caller_address == reward_address,
                Error::POOL_CLAIM_REWARDS_FROM_UNAUTHORIZED_ADDRESS
            );
            self.update_index_and_update_rewards(ref :pool_member_info);
            let rewards = pool_member_info.unclaimed_rewards;
            let erc20_dispatcher = self.erc20_dispatcher.read();
            self.send_rewards_to_member(ref :pool_member_info, :pool_member, :erc20_dispatcher);
            self.pool_member_info.write(pool_member, Option::Some(pool_member_info));
            rewards
        }

        fn switch_delegation_pool(
            ref self: ContractState,
            to_staker: ContractAddress,
            to_pool: ContractAddress,
            amount: Amount
        ) -> Amount {
            assert_with_err(amount.is_non_zero(), Error::AMOUNT_IS_ZERO);
            let pool_member = get_caller_address();
            let mut pool_member_info = self.get_pool_member_info(:pool_member);
            assert_with_err(
                pool_member_info.unpool_time.is_some(), Error::MISSING_UNDELEGATE_INTENT
            );
            assert_with_err(pool_member_info.unpool_amount >= amount, Error::AMOUNT_TOO_HIGH);
            let reward_address = pool_member_info.reward_address;
            pool_member_info.unpool_amount -= amount;
            if pool_member_info.unpool_amount.is_zero() && pool_member_info.amount.is_zero() {
                // Claim rewards.
                let erc20_dispatcher = self.erc20_dispatcher.read();
                self.send_rewards_to_member(ref :pool_member_info, :pool_member, :erc20_dispatcher);
                self.remove_pool_member(:pool_member);
            } else {
                // One of pool_member_info.unpool_amount or pool_member_info.amount is non-zero.
                if pool_member_info.unpool_amount.is_zero() {
                    pool_member_info.unpool_time = Option::None;
                }
                self.pool_member_info.write(pool_member, Option::Some(pool_member_info));
            }
            let switch_pool_data = SwitchPoolData { pool_member, reward_address };
            let mut serialized_data = array![];
            switch_pool_data.serialize(ref output: serialized_data);
            // TODO: emit event
            self
                .staking_pool_dispatcher
                .read()
                .switch_staking_delegation_pool(
                    :to_staker,
                    :to_pool,
                    switched_amount: amount,
                    data: serialized_data.span(),
                    identifier: pool_member.into()
                );
            pool_member_info.unpool_amount
        }

        fn enter_delegation_pool_from_staking_contract(
            ref self: ContractState, amount: Amount, index: Index, data: Span<felt252>
        ) {
            assert_with_err(amount.is_non_zero(), Error::AMOUNT_IS_ZERO);
            assert_with_err(
                get_caller_address() == self.staking_pool_dispatcher.read().contract_address,
                Error::CALLER_IS_NOT_STAKING_CONTRACT
            );
            let mut serialized = data;
            let switch_pool_data: SwitchPoolData = Serde::deserialize(ref :serialized)
                .expect_with_err(Error::SWITCH_POOL_DATA_DESERIALIZATION_FAILED);
            let pool_member = switch_pool_data.pool_member;
            let pool_member_info = match self.pool_member_info.read(pool_member) {
                Option::Some(mut pool_member_info) => {
                    assert_with_err(
                        pool_member_info.reward_address == switch_pool_data.reward_address,
                        Error::REWARD_ADDRESS_MISMATCH
                    );
                    self.update_rewards(ref :pool_member_info, updated_index: index);
                    pool_member_info.amount += amount;
                    pool_member_info
                },
                Option::None => {
                    InternalPoolMemberInfo {
                        reward_address: switch_pool_data.reward_address,
                        amount,
                        index,
                        unclaimed_rewards: Zero::zero(),
                        commission: self.commission.read(),
                        unpool_time: Option::None,
                        unpool_amount: Zero::zero(),
                    }
                }
            };
            self.pool_member_info.write(pool_member, Option::Some(pool_member_info));
            self
                .emit(
                    Events::PoolMemberBalanceChanged {
                        pool_member,
                        old_delegated_stake: pool_member_info.amount - amount,
                        new_delegated_stake: pool_member_info.amount
                    }
                );
        }

        fn set_final_staker_index(ref self: ContractState, final_staker_index: Index) {
            assert_with_err(
                get_caller_address() == self.staking_pool_dispatcher.read().contract_address,
                Error::CALLER_IS_NOT_STAKING_CONTRACT
            );
            assert_with_err(
                self.final_staker_index.read().is_none(), Error::FINAL_STAKER_INDEX_ALREADY_SET
            );
            self.final_staker_index.write(Option::Some(final_staker_index));
            self
                .emit(
                    Events::FinalIndexSet {
                        staker_address: self.staker_address.read(), final_staker_index
                    }
                );
        }

        fn change_reward_address(ref self: ContractState, reward_address: ContractAddress) {
            let pool_member = get_caller_address();
            let mut pool_member_info = self.get_pool_member_info(:pool_member);
            let old_address = pool_member_info.reward_address;
            pool_member_info.reward_address = reward_address;
            self.pool_member_info.write(pool_member, Option::Some(pool_member_info));
            self
                .emit(
                    Events::PoolMemberRewardAddressChanged {
                        pool_member, new_address: reward_address, old_address
                    }
                );
        }

        fn pool_member_info(self: @ContractState, pool_member: ContractAddress) -> PoolMemberInfo {
            self.get_pool_member_info(:pool_member).into()
        }

        fn contract_parameters(self: @ContractState) -> PoolContractInfo {
            PoolContractInfo {
                staker_address: self.staker_address.read(),
                final_staker_index: self.final_staker_index.read(),
                staking_contract: self.staking_pool_dispatcher.read().contract_address,
                token_address: self.erc20_dispatcher.read().contract_address,
                commission: self.commission.read(),
            }
        }

        fn update_commission_from_staking_contract(
            ref self: ContractState, commission: Commission
        ) {
            let old_commission = self.commission.read();
            if commission == old_commission {
                return;
            }
            assert_with_err(commission < old_commission, Error::CANNOT_INCREASE_COMMISSION);
            assert_with_err(
                get_caller_address() == self.staking_pool_dispatcher.read().contract_address,
                Error::CALLER_IS_NOT_STAKING_CONTRACT
            );
            self.commission.write(commission);
        }
    }

    #[generate_trait]
    pub(crate) impl InternalPoolFunctions of InternalPoolFunctionsTrait {
        fn get_pool_member_info(
            self: @ContractState, pool_member: ContractAddress
        ) -> InternalPoolMemberInfo {
            self
                .pool_member_info
                .read(pool_member)
                .expect_with_err(Error::POOL_MEMBER_DOES_NOT_EXIST)
        }

        fn remove_pool_member(ref self: ContractState, pool_member: ContractAddress) {
            let pool_member_info = self.get_pool_member_info(:pool_member);
            self.pool_member_info.write(pool_member, Option::None);
            self
                .emit(
                    Events::DeletePoolMember {
                        pool_member, reward_address: pool_member_info.reward_address
                    }
                );
        }

        fn receive_index_and_funds_from_staker(self: @ContractState) -> Index {
            if let Option::Some(final_index) = self.final_staker_index.read() {
                // If the staker is inactive, the staker already pushed index and funds.
                return final_index;
            }
            let staking_pool_dispatcher = self.staking_pool_dispatcher.read();
            staking_pool_dispatcher.claim_delegation_pool_rewards(self.staker_address.read())
        }

        /// Calculates the rewards for a pool member.
        ///
        /// The caller for this function should validate that the pool member exists.
        ///
        /// rewards formula:
        /// $$ rewards = (staker\_index-pooler\_index) * pooler\_amount $$
        ///
        /// Fields that are changed in pool_member_info:
        /// - unclaimed_rewards
        /// - index
        fn update_rewards(
            ref self: ContractState,
            ref pool_member_info: InternalPoolMemberInfo,
            updated_index: Index
        ) {
            let interest: Index = updated_index - pool_member_info.index;
            pool_member_info.index = updated_index;
            let rewards_including_commission = compute_rewards_rounded_down(
                amount: pool_member_info.amount, :interest
            );
            let commission_amount = compute_commission_amount_rounded_up(
                :rewards_including_commission, commission: pool_member_info.commission
            );
            let rewards = rewards_including_commission - commission_amount;
            pool_member_info.unclaimed_rewards += rewards;
            pool_member_info.commission = self.commission.read();
        }

        fn update_index_and_update_rewards(
            ref self: ContractState, ref pool_member_info: InternalPoolMemberInfo
        ) {
            let updated_index = self.receive_index_and_funds_from_staker();
            self.update_rewards(ref :pool_member_info, :updated_index)
        }

        fn assert_staker_is_active(self: @ContractState) {
            assert_with_err(self.is_staker_active(), Error::STAKER_INACTIVE);
        }

        fn is_staker_active(self: @ContractState) -> bool {
            self.final_staker_index.read().is_none()
        }

        fn undelegate_from_staking_contract_intent(
            self: @ContractState, pool_member: ContractAddress, amount: Amount
        ) -> TimeStamp {
            if !self.is_staker_active() {
                // Don't allow intent if an intent is already in progress and the staker is erased.
                assert_with_err(
                    self.get_pool_member_info(:pool_member).unpool_time.is_none(),
                    Error::UNDELEGATE_IN_PROGRESS
                );
                return get_block_timestamp();
            }
            let staking_pool_dispatcher = self.staking_pool_dispatcher.read();
            let staker_address = self.staker_address.read();
            staking_pool_dispatcher
                .remove_from_delegation_pool_intent(
                    :staker_address, identifier: pool_member.into(), :amount
                )
        }

        /// Sends the rewards to the `pool_member`'s reward address.
        /// Important note:
        /// After calling this function, one must write the updated pool_member_info to the storage.
        fn send_rewards_to_member(
            ref self: ContractState,
            ref pool_member_info: InternalPoolMemberInfo,
            pool_member: ContractAddress,
            erc20_dispatcher: IERC20Dispatcher
        ) {
            let reward_address = pool_member_info.reward_address;
            let amount = pool_member_info.unclaimed_rewards;

            erc20_dispatcher.checked_transfer(recipient: reward_address, amount: amount.into());
            pool_member_info.unclaimed_rewards = Zero::zero();

            self.emit(Events::PoolMemberRewardClaimed { pool_member, reward_address, amount });
        }
    }
}
