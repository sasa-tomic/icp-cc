use icp_core::favorites as fav;

fn with_temp_config<T: FnOnce() -> R, R>(f: T) -> R {
    let dir = tempfile::tempdir().unwrap();
    std::env::set_var("XDG_CONFIG_HOME", dir.path());
    let r = f();
    // ensure file operations flushed before tempdir drop
    drop(dir);
    r
}

#[test]
fn add_list_remove_favorites_roundtrip() {
    with_temp_config(|| {
        // start empty
        let list = fav::list().expect("list ok");
        assert!(list.is_empty());

        // add entry
        fav::add(fav::FavoriteEntry {
            canister_id: "ryjl3-tyaaa-aaaaa-aaaba-cai".into(),
            method: "greet".into(),
            label: Some("NNS greet".into()),
        })
        .expect("add ok");

        // add duplicate should be idempotent
        fav::add(fav::FavoriteEntry {
            canister_id: "ryjl3-tyaaa-aaaaa-aaaba-cai".into(),
            method: "greet".into(),
            label: Some("Duplicate".into()),
        })
        .expect("add duplicate ok");

        let list = fav::list().expect("list ok");
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].method, "greet");

        // remove
        fav::remove("ryjl3-tyaaa-aaaaa-aaaba-cai", "greet").expect("remove ok");
        let list = fav::list().expect("list ok");
        assert!(list.is_empty());
    });
}
