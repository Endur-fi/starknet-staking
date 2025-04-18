/// #[cfg(feature: 'staking_test_mods')]
mod align_upg_vars_eic;
mod assign_root_gov_eic;
mod eic;
pub mod errors;
pub mod interface;
pub mod interface_v0;
pub mod objects;
// /// #[cfg(test)]
mod pause_test;
pub mod staker_balance_trace;
pub mod staking;
/// #[cfg(feature: 'staking_test_mods')]
mod test;
