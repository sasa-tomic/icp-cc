use icp_core::canister_client::fetch_candid;

#[test]
fn fetch_candid_registry_mainnet_succeeds_or_skips_without_network_feature() {
    // NNS Registry canister on mainnet
    let canister_id = "rwlgt-iiaaa-aaaaa-aaaaa-cai";

    let result = fetch_candid(canister_id, None);

    match result {
        Ok(candid_text) => {
            assert!(!candid_text.trim().is_empty(), "candid response was empty");
            assert!(
                candid_text.contains("service "),
                "unexpected candid content: {candid_text}"
            );
        }
        Err(e) => panic!("fetch_candid failed: {e}"),
    }
}
