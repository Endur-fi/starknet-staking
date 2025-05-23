use staking_test::constants::MAX_C_NUM;
use starkware_utils::errors::{Describable, ErrorDisplay};

#[derive(Drop)]
pub enum Error {
    TOTAL_SUPPLY_NOT_AMOUNT_TYPE,
    UNAUTHORIZED_MESSAGE_SENDER,
    C_NUM_OUT_OF_RANGE,
}

impl DescribableError of Describable<Error> {
    fn describe(self: @Error) -> ByteArray {
        match self {
            Error::UNAUTHORIZED_MESSAGE_SENDER => "Unauthorized message sender",
            Error::TOTAL_SUPPLY_NOT_AMOUNT_TYPE => "Total supply does not fit in u128",
            Error::C_NUM_OUT_OF_RANGE => format!("C Numerator out of range (0-{})", MAX_C_NUM),
        }
    }
}
