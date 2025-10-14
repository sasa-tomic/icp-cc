use icp_core::canister_client::{parse_candid_interface, MethodKind};

#[test]
fn parses_methods_and_kinds() {
    let did = r#"
        service : {
            greet: (text) -> (text) query;
            compute: (int, int) -> (int);
            inspect: () -> () composite_query;
        }
    "#;
    let parsed = parse_candid_interface(did).expect("parse ok");
    let mut by_name = std::collections::HashMap::new();
    for m in parsed.methods {
        by_name.insert(m.name.clone(), m);
    }
    let greet = by_name.get("greet").unwrap();
    assert_eq!(greet.kind, MethodKind::Query);
    assert_eq!(greet.args, vec!["text"]);
    assert_eq!(greet.rets, vec!["text"]);

    let compute = by_name.get("compute").unwrap();
    assert_eq!(compute.kind, MethodKind::Update);
    assert_eq!(compute.args, vec!["int", "int"]);
    assert_eq!(compute.rets, vec!["int"]);

    let inspect = by_name.get("inspect").unwrap();
    assert_eq!(inspect.kind, MethodKind::CompositeQuery);
    assert!(inspect.args.is_empty());
    assert!(inspect.rets.is_empty());
}
