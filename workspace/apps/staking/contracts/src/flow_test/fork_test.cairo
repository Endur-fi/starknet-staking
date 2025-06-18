use core::num::traits::Zero;
use staking::flow_test::flows;
use staking::flow_test::utils::{
    StakingTrait, SystemDelegatorTrait, SystemFactoryTrait, SystemReplaceabilityV1Trait,
    SystemStakerTrait, SystemTrait, test_flow_mainnet,
};
use staking::staking::errors::Error;
use starkware_utils::errors::Describable;
use starkware_utils::types::time::time::Time;
use starkware_utils_testing::test_utils::{TokenTrait, assert_panic_with_error};

#[test]
#[fork("MAINNET_LATEST")]
fn basic_stake_flow_regression_test() {
    let mut flow = flows::BasicStakeFlow {};
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn set_open_for_delegation_regression_test() {
    let mut flow = flows::SetOpenForDelegationFlow {};
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn delegator_intent_after_staker_action_regression_test() {
    let mut flow = flows::DelegatorIntentAfterStakerActionFlow {};
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn delegator_intent_regression_test() {
    let mut flow = flows::DelegatorIntentFlow {};
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn operations_after_dead_staker_regression_test() {
    let mut flow = flows::OperationsAfterDeadStakerFlow {};
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn delegator_didnt_update_after_staker_update_commission_regression_test() {
    let mut flow = flows::DelegatorDidntUpdateAfterStakerUpdateCommissionFlow {};
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn delegator_updated_after_staker_update_commission_regression_test() {
    let mut flow = flows::DelegatorUpdatedAfterStakerUpdateCommissionFlow {};
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn staker_intent_last_action_first_regression_test() {
    let mut flow = flows::StakerIntentLastActionFirstFlow {};
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn staker_info_after_upgrade_regression_test() {
    let mut flow = flows::StakerInfoAfterUpgradeFlow {
        staker: Option::None, staker_info: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn staker_info_with_pool_after_upgrade_regression_test() {
    let mut flow = flows::StakerInfoWithPoolAfterUpgradeFlow {
        staker: Option::None, staker_info: Option::None, pool_address: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn staker_info_unstake_after_upgrade_regression_test() {
    let mut flow = flows::StakerInfoUnstakeAfterUpgradeFlow {
        staker: Option::None, staker_info: Option::None, pool_address: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn internal_staker_info_after_upgrade_regression_test() {
    let mut flow = flows::InternalStakerInfoAfterUpgradeFlow {
        staker: Option::None, staker_info: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn internal_staker_info_with_pool_after_upgrade_regression_test() {
    let mut flow = flows::InternalStakerInfoWithPoolAfterUpgradeFlow {
        staker: Option::None, staker_info: Option::None, pool_address: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn internal_staker_info_unstake_after_upgrade_regression_test() {
    let mut flow = flows::InternalStakerInfoUnstakeAfterUpgradeFlow {
        staker: Option::None, staker_info: Option::None, pool_address: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn pool_upgrade_flow_regression_test() {
    let mut flow = flows::PoolUpgradeFlow {
        pool_address: Option::None,
        delegator: Option::None,
        delegated_amount: Zero::zero(),
        staker: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn pool_claim_rewards_after_upgrade_regression_test() {
    let mut flow = flows::PoolClaimRewardsAfterUpgradeFlow {
        pool_address: Option::None,
        staker: Option::None,
        delegator: Option::None,
        delegator_info: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn pool_member_info_after_upgrade_regression_test() {
    let mut flow = flows::PoolMemberInfoAfterUpgradeFlow {
        pool_address: Option::None,
        delegator: Option::None,
        delegator_info: Option::None,
        staker: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn pool_member_info_undelegate_after_upgrade_regression_test() {
    let mut flow = flows::PoolMemberInfoUndelegateAfterUpgradeFlow {
        pool_address: Option::None,
        delegator: Option::None,
        delegator_info: Option::None,
        staker: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn increase_delegation_after_upgrade_regression_test() {
    let mut flow = flows::IncreaseDelegationAfterUpgradeFlow {
        pool_address: Option::None,
        delegator: Option::None,
        delegated_amount: Option::None,
        staker: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn change_commission_after_upgrade_regression_test() {
    let mut flow = flows::ChangeCommissionAfterUpgradeFlow {
        staker: Option::None, pool_address: Option::None, commission: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn delegator_claim_rewards_after_upgrade_regression_test() {
    let mut flow = flows::DelegatorClaimRewardsAfterUpgradeFlow {
        pool_address: Option::None, delegator: Option::None, staker: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn delegator_partial_intent_after_upgrade_regression_test() {
    let mut flow = flows::DelegatorPartialIntentAfterUpgradeFlow {
        pool_address: Option::None,
        delegator: Option::None,
        delegated_amount: Option::None,
        staker: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn increase_stake_after_upgrade_regression_test() {
    let mut flow = flows::IncreaseStakeAfterUpgradeFlow {
        staker: Option::None, stake_amount: Option::None, pool_address: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn pool_change_balance_after_upgrade_regression_test() {
    let mut flow = flows::PoolChangeBalanceAfterUpgradeFlow {
        pool_address: Option::None,
        staker: Option::None,
        delegator: Option::None,
        delegator_info: Option::None,
        delegated_amount: Zero::zero(),
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn delegator_action_after_upgrade_regression_test() {
    let mut flow = flows::DelegatorActionAfterUpgradeFlow {
        pool_address: Option::None, delegator: Option::None, staker: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn delegator_intent_after_upgrade_regression_test() {
    let mut flow = flows::DelegatorIntentAfterUpgradeFlow {
        pool_address: Option::None,
        delegator: Option::None,
        delegated_amount: Option::None,
        staker: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn staker_intent_after_upgrade_regression_test() {
    let mut flow = flows::StakerIntentAfterUpgradeFlow {
        staker: Option::None, pool_address: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn staker_action_after_upgrade_regression_test() {
    let mut flow = flows::StakerActionAfterUpgradeFlow {
        staker: Option::None, pool_address: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
#[should_panic(expected: "Unstake is in progress, staker is in an exit window")]
fn staker_attest_after_intent_regression_test() {
    let mut flow = flows::StakerAttestAfterIntentFlow { staker: Option::None };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn delegator_switch_after_upgrade_regression_test() {
    let mut flow = flows::DelegatorSwitchAfterUpgradeFlow {
        pool_address: Option::None,
        delegator: Option::None,
        delegated_amount: Option::None,
        staker: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn staker_migration_regression_test() {
    let mut flow = flows::StakerMigrationFlow { staker: Option::None, staker_info: Option::None };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn delegator_intent_before_claim_rewards_after_regression_test() {
    let mut flow = flows::DelegatorIntentBeforeClaimRewardsAfterFlow {
        staker: Option::None, pool_address: Option::None, delegator: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn set_open_for_delegation_after_upgrade_flow_test() {
    let mut flow = flows::SetOpenForDelegationAfterUpgradeFlow { staker: Option::None };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
#[ignore]
// TODO: Test when migration for the new version is implemented.
fn total_stake_after_upgrade_flow_test() {
    let mut flow = flows::TotalStakeAfterUpgradeFlow {
        pool_address: Option::None,
        pool_address2: Option::None,
        total_stake: Option::None,
        staker: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
#[should_panic(expected: "Staker migration is not allowed, staker has a pool")]
fn staker_migration_has_pool_flow_test() {
    let mut flow = flows::StakerMigrationHasPoolFlow { staker_address: Option::None };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn claim_rewards_with_non_upgraded_pool_flow_test() {
    let mut flow = flows::ClaimRewardsWithNonUpgradedPoolFlow {
        pool_address: Option::None,
        first_delegator: Option::None,
        first_delegator_info: Option::None,
        second_delegator: Option::None,
        second_delegator_info: Option::None,
        third_delegator: Option::None,
        third_delegator_info: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn delegator_action_with_non_upgraded_pool_regression_test() {
    let mut flow = flows::DelegatorActionWithNonUpgradedPoolFlow {
        staker: Option::None,
        pool_address: Option::None,
        first_delegator: Option::None,
        first_delegator_info: Option::None,
        second_delegator: Option::None,
        second_delegator_info: Option::None,
        third_delegator: Option::None,
        third_delegator_info: Option::None,
        initial_reward_supplier_balance: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn switch_with_non_upgraded_pool_regression_test() {
    let mut flow = flows::SwitchWithNonUpgradedPoolFlow {
        pool_address: Option::None,
        first_delegator: Option::None,
        second_delegator: Option::None,
        stake_amount: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn delegator_exit_before_enter_after_regression_test() {
    let mut flow = flows::DelegatorExitBeforeEnterAfterFlow {
        pool_address: Option::None, delegator: Option::None, staker: Option::None,
    };
    test_flow_mainnet(ref :flow);
}

#[test]
#[fork("MAINNET_LATEST")]
fn delegator_exit_with_non_upgraded_pool_regression_test() {
    let mut flow = flows::DelegatorExitWithNonUpgradedPoolFlow {
        pool_address: Option::None,
        first_delegator: Option::None,
        first_delegator_info: Option::None,
        second_delegator: Option::None,
        second_delegator_info: Option::None,
        third_delegator: Option::None,
        third_delegator_info: Option::None,
    };
    test_flow_mainnet(ref :flow);
}
