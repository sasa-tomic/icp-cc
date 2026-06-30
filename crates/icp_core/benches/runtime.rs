use criterion::{black_box, criterion_group, criterion_main, Criterion};
use icp_core::{execute_js_json, js_app_init, js_app_update, js_app_view};

const JS_COUNTER: &str = r#"
    function init(arg) {
        var start = (arg && arg.start) || 0;
        return { state: { count: start, last: null }, effects: [] };
    }
    function view(state) {
        return { type: "column", props: {}, children: [
            { type: "text", props: { text: String(state.count) } }
        ] };
    }
    function update(msg, state) {
        var t = (msg && msg.type) || "";
        if (t === "inc") { state.count = (state.count || 0) + 1; }
        state.last = msg;
        return { state: state, effects: [] };
    }
"#;

const JS_ALL_HELPERS: &str = "(icp_call(), icp_batch({calls:[]}), icp_message(), icp_ui_list({items:[]}), icp_result_display({}), icp_searchable_list({items:[]}), icp_section({}), icp_table({}), icp_format_number(1,2), icp_format_icp(1,8), icp_format_timestamp(1), icp_format_bytes(1), icp_truncate('x',1), icp_filter_items([],'c','x'), icp_sort_items([],'c',true), icp_group_by([],'c'))";

fn bench_cold_start(c: &mut Criterion) {
    let mut g = c.benchmark_group("cold_start");
    g.bench_function("js_execute", |b| {
        b.iter(|| {
            black_box(execute_js_json(black_box("1+2"), None).unwrap());
        });
    });
    g.bench_function("js_app_init", |b| {
        b.iter(|| black_box(js_app_init(black_box(JS_COUNTER), None, 1000)));
    });
    g.finish();
}

fn bench_helpers_throughput(c: &mut Criterion) {
    let mut g = c.benchmark_group("helpers_throughput");
    g.bench_function("js_all_16", |b| {
        b.iter(|| black_box(execute_js_json(black_box(JS_ALL_HELPERS), None).unwrap()));
    });
    g.finish();
}

fn bench_lifecycle_roundtrip(c: &mut Criterion) {
    let mut g = c.benchmark_group("lifecycle_roundtrip");
    g.bench_function("js_init_view_update", |b| {
        b.iter(|| {
            let init = js_app_init(black_box(JS_COUNTER), Some(r#"{"start":0}"#), 1000);
            let v: serde_json::Value = serde_json::from_str(&init).unwrap();
            let state = v["state"].to_string();
            black_box(js_app_view(black_box(JS_COUNTER), &state, 1000));
            black_box(js_app_update(
                black_box(JS_COUNTER),
                r#"{"type":"inc"}"#,
                &state,
                1000,
            ));
        });
    });
    g.finish();
}

criterion_group!(
    benches,
    bench_cold_start,
    bench_helpers_throughput,
    bench_lifecycle_roundtrip
);
criterion_main!(benches);
