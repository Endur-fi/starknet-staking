use staking::staking::staking::Staking::COMMISSION_DENOMINATOR;
use starkware_utils::errors::{Describable, ErrorDisplay};

#[derive(Drop)]
pub enum Error {
    AMOUNT_LESS_THAN_MIN_STAKE,
    COMMISSION_OUT_OF_RANGE,
    UNSTAKE_IN_PROGRESS,
    POOL_ADDRESS_DOES_NOT_EXIST,
    CLAIM_REWARDS_FROM_UNAUTHORIZED_ADDRESS,
    MISSING_UNSTAKE_INTENT,
    CALLER_IS_NOT_POOL_CONTRACT,
    MISSING_POOL_CONTRACT,
    DELEGATION_POOL_MISMATCH,
    GLOBAL_INDEX_DIFF_NOT_INDEX_TYPE,
    GLOBAL_INDEX_DIFF_COMPUTATION_OVERFLOW,
    UNEXPECTED_BALANCE,
    STAKER_ALREADY_HAS_POOL,
    CONTRACT_IS_PAUSED,
    INVALID_UNDELEGATE_INTENT_VALUE,
    OPERATIONAL_NOT_ELIGIBLE,
    OPERATIONAL_IN_USE,
    CALLER_IS_ZERO_ADDRESS,
    SELF_SWITCH_NOT_ALLOWED,
    ILLEGAL_EXIT_DURATION,
    CALLER_IS_NOT_ATTESTATION_CONTRACT,
    INTERNAL_STAKER_INFO_OUTDATED_VERSION,
    INTERNAL_STAKER_INFO_ALREADY_UPDATED,
    INVALID_EPOCH_LENGTH,
    EPOCH_INFO_ALREADY_UPDATED,
    EPOCH_INFO_UPDATED_IN_FIRST_EPOCH,
    MAX_COMMISSION_TOO_LOW,
    EXPIRATION_EPOCH_TOO_FAR,
    COMMISSION_COMMITMENT_EXISTS,
    COMMISSION_COMMITMENT_NOT_SET,
    EXPIRATION_EPOCH_TOO_EARLY,
    INVALID_EPOCH_DURATION,
    PENULTIMATE_NOT_EXIST,
    INVALID_STARTING_BLOCK,
    INVALID_PENULTIMATE,
    STAKER_BALANCE_NOT_INITIALIZED,
    STAKER_ADDRESS_ALREADY_USED,
}

impl DescribableError of Describable<Error> {
    fn describe(self: @Error) -> ByteArray {
        match self {
            Error::OPERATIONAL_NOT_ELIGIBLE => "Operational address had not been declared by staker",
            Error::OPERATIONAL_IN_USE => "Operational address is in use",
            Error::AMOUNT_LESS_THAN_MIN_STAKE => "Amount is less than min stake - try again with enough funds",
            Error::COMMISSION_OUT_OF_RANGE => format!(
                "Commission is out of range, expected to be 0-{}", COMMISSION_DENOMINATOR,
            ),
            Error::POOL_ADDRESS_DOES_NOT_EXIST => "Pool address does not exist",
            Error::MISSING_UNSTAKE_INTENT => "Unstake intent is missing",
            Error::UNSTAKE_IN_PROGRESS => "Unstake is in progress, staker is in an exit window",
            Error::CLAIM_REWARDS_FROM_UNAUTHORIZED_ADDRESS => "Claim rewards must be called from staker address or reward address",
            Error::CALLER_IS_NOT_POOL_CONTRACT => "Caller is not pool contract",
            Error::MISSING_POOL_CONTRACT => "Staker does not have a pool contract",
            Error::DELEGATION_POOL_MISMATCH => "to_pool is not the delegation pool contract for to_staker",
            Error::GLOBAL_INDEX_DIFF_NOT_INDEX_TYPE => "Global index diff does not fit in u128",
            Error::GLOBAL_INDEX_DIFF_COMPUTATION_OVERFLOW => "Overflow during computation global index diff",
            Error::UNEXPECTED_BALANCE => "Unexpected balance",
            Error::STAKER_ALREADY_HAS_POOL => "Staker already has a pool",
            Error::CONTRACT_IS_PAUSED => "Contract is paused",
            Error::INVALID_UNDELEGATE_INTENT_VALUE => "Invalid undelegate intent value",
            Error::CALLER_IS_ZERO_ADDRESS => "Zero address caller is not allowed",
            Error::SELF_SWITCH_NOT_ALLOWED => "SELF_SWITCH_NOT_ALLOWED",
            Error::ILLEGAL_EXIT_DURATION => "ILLEGAL_EXIT_DURATION",
            Error::CALLER_IS_NOT_ATTESTATION_CONTRACT => "Caller is not attestation contract",
            Error::INTERNAL_STAKER_INFO_OUTDATED_VERSION => "Outdated version of Internal Staker Info",
            Error::INTERNAL_STAKER_INFO_ALREADY_UPDATED => "Internal Staker Info is already up-to-date",
            Error::INVALID_EPOCH_LENGTH => "Invalid epoch length, must be greater than 0",
            Error::EPOCH_INFO_ALREADY_UPDATED => "Epoch info already updated in this epoch",
            Error::EPOCH_INFO_UPDATED_IN_FIRST_EPOCH => "Epoch info can not be updated in the first epoch",
            Error::MAX_COMMISSION_TOO_LOW => "Max commission is too low, needs to be smaller or equal to current commission",
            Error::EXPIRATION_EPOCH_TOO_FAR => "Expiration epoch is too far, should be at most 1 year",
            Error::COMMISSION_COMMITMENT_EXISTS => "Commission commitment exists",
            Error::COMMISSION_COMMITMENT_NOT_SET => "Commission commitment not set",
            Error::EXPIRATION_EPOCH_TOO_EARLY => "Expiration epoch is too early, should be later then current epoch",
            Error::INVALID_EPOCH_DURATION => "Invalid epoch duration, must be greater than 0",
            Error::PENULTIMATE_NOT_EXIST => "Penultimate balance does not exist, staker balance at this epoch is 0",
            Error::INVALID_STARTING_BLOCK => "Invalid starting block, must be greater than or equal to current block number",
            Error::INVALID_PENULTIMATE => "Invalid penultimate epoch, must be lower than or equal to current epoch",
            Error::STAKER_BALANCE_NOT_INITIALIZED => "Staker balance is not initialized",
            Error::STAKER_ADDRESS_ALREADY_USED => "Staker address is already used",
        }
    }
}
