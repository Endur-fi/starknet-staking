use core::num::traits::Zero;
use staking::staker_balance_trace::mock::{IMockTrace, MockTrace};
use staking::staker_balance_trace::trace::{StakerBalanceTrait};

fn CONTRACT_STATE() -> MockTrace::ContractState {
    MockTrace::contract_state_for_testing()
}

#[test]
fn test_insert() {
    let mut mock_trace = CONTRACT_STATE();

    let (prev, new) = mock_trace.insert(key: 100, value: StakerBalanceTrait::new(amount: 1000));
    assert_eq!(prev, Zero::zero());
    assert_eq!(new, StakerBalanceTrait::new(amount: 1000));

    let (prev, new) = mock_trace.insert(key: 200, value: StakerBalanceTrait::new(amount: 2000));
    assert_eq!(prev, StakerBalanceTrait::new(amount: 1000));
    assert_eq!(new, StakerBalanceTrait::new(amount: 2000));
    assert_eq!(mock_trace.length(), 2);

    let (prev, new) = mock_trace.insert(key: 200, value: StakerBalanceTrait::new(amount: 500));
    assert_eq!(prev, StakerBalanceTrait::new(amount: 2000));
    assert_eq!(new, StakerBalanceTrait::new(amount: 500));
    assert_eq!(mock_trace.length(), 2);
}

#[test]
#[should_panic(expected: "Unordered insertion")]
fn test_insert_unordered_insertion() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.insert(200, StakerBalanceTrait::new(amount: 200));
    mock_trace.insert(100, StakerBalanceTrait::new(amount: 100)); // This should panic
}

#[test]
#[should_panic(expected: "Empty trace")]
fn test_latest_empty_trace() {
    let mut mock_trace = CONTRACT_STATE();

    let _ = mock_trace.latest();
}

#[test]
fn test_latest() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.insert(100, StakerBalanceTrait::new(amount: 100));
    mock_trace.insert(200, StakerBalanceTrait::new(amount: 200));

    let (key, value) = mock_trace.latest();
    assert_eq!(key, 200);
    assert_eq!(value, StakerBalanceTrait::new(amount: 200));
}

#[test]
fn test_length() {
    let mut mock_trace = CONTRACT_STATE();

    assert_eq!(mock_trace.length(), 0);

    mock_trace.insert(100, StakerBalanceTrait::new(amount: 100));
    assert_eq!(mock_trace.length(), 1);

    mock_trace.insert(200, StakerBalanceTrait::new(amount: 200));
    assert_eq!(mock_trace.length(), 2);
}

#[test]
fn test_upper_lookup() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.insert(100, StakerBalanceTrait::new(amount: 100));
    mock_trace.insert(200, StakerBalanceTrait::new(amount: 200));

    assert_eq!(mock_trace.upper_lookup(100), StakerBalanceTrait::new(amount: 100));
    assert_eq!(mock_trace.upper_lookup(150), StakerBalanceTrait::new(amount: 100));
    assert_eq!(mock_trace.upper_lookup(200), StakerBalanceTrait::new(amount: 200));
    assert_eq!(mock_trace.upper_lookup(250), StakerBalanceTrait::new(amount: 200));
}

#[test]
fn test_latest_mutable() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.insert(100, StakerBalanceTrait::new(amount: 100));
    mock_trace.insert(200, StakerBalanceTrait::new(amount: 200));

    let latest = mock_trace.latest_mutable();
    assert_eq!(latest, StakerBalanceTrait::new(amount: 200));
}
