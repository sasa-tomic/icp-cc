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
        Err(e) => {
            let err_text = e.to_string();
            if err_text.contains("network error")
                || err_text.contains("Connection refused")
                || err_text.contains("TLS error")
            {
                eprintln!("skipping fetch_candid test due to network error: {err_text}");
                return;
            }
            panic!("fetch_candid failed: {err_text}");
        }
    }
}
