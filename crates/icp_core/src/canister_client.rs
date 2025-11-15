use base64::Engine as _;
use candid::types::value::{IDLField, IDLValue, VariantValue};
use candid::types::Label;
use candid::types::{Field, Type};
use candid::types::{FuncMode, TypeEnv, TypeInner};
use candid::{IDLArgs, Principal};
use candid::{Int as CandidInt, Nat as CandidNat, Principal as CanisterPrincipal};
use candid_parser::{check_prog, IDLProg};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::vec::Vec as StdVec;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum CanisterClientError {
    #[error("invalid canister id: {0}")]
    InvalidCanisterId(String),
    #[error("candid parse error: {0}")]
    CandidParse(String),
    #[error("network error: {0}")]
    Net(String),
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum MethodKind {
    Query,
    Update,
    CompositeQuery,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct MethodInfo {
    pub name: String,
    pub kind: MethodKind,
    pub args: Vec<String>,
    pub rets: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ParsedInterface {
    pub methods: Vec<MethodInfo>,
}
fn label_to_string(label: &Label) -> String {
    match label {
        Label::Named(n) => n.to_string(),
        Label::Id(i) => i.to_string(),
        Label::Unnamed(i) => i.to_string(),
    }
}

fn idl_value_to_json(value: &IDLValue) -> serde_json::Value {
    match value {
        IDLValue::Null | IDLValue::Reserved | IDLValue::None => serde_json::Value::Null,
        IDLValue::Bool(b) => serde_json::Value::Bool(*b),
        IDLValue::Text(s) => serde_json::Value::String(s.clone()),
        // Big integers are rendered as strings to avoid JSON number precision loss
        IDLValue::Nat(n) => serde_json::Value::String(n.to_string()),
        IDLValue::Int(i) => serde_json::Value::String(i.to_string()),
        IDLValue::Number(s) => serde_json::Value::String(s.clone()),
        IDLValue::Nat8(v) => serde_json::Value::Number((*v).into()),
        IDLValue::Nat16(v) => serde_json::json!(*v),
        IDLValue::Nat32(v) => serde_json::json!(*v),
        IDLValue::Nat64(v) => serde_json::Value::String(v.to_string()),
        IDLValue::Int8(v) => serde_json::json!(*v),
        IDLValue::Int16(v) => serde_json::json!(*v),
        IDLValue::Int32(v) => serde_json::json!(*v),
        IDLValue::Int64(v) => serde_json::Value::String(v.to_string()),
        IDLValue::Float32(v) => serde_json::json!(*v),
        IDLValue::Float64(v) => serde_json::json!(*v),
        IDLValue::Principal(p) => serde_json::Value::String(p.to_text()),
        IDLValue::Opt(inner) => idl_value_to_json(inner.as_ref()),
        IDLValue::Vec(vs) => serde_json::Value::Array(vs.iter().map(idl_value_to_json).collect()),
        IDLValue::Record(fields) => {
            let mut map = serde_json::Map::new();
            for IDLField { id, val } in fields.iter() {
                map.insert(label_to_string(id), idl_value_to_json(val));
            }
            serde_json::Value::Object(map)
        }
        IDLValue::Variant(VariantValue(field, _idx)) => {
            let mut map = serde_json::Map::new();
            map.insert(label_to_string(&field.id), idl_value_to_json(&field.val));
            serde_json::Value::Object(map)
        }
        IDLValue::Service(p) => serde_json::Value::String(p.to_text()),
        IDLValue::Func(principal, method) => {
            let mut map = serde_json::Map::new();
            map.insert(
                "principal".to_string(),
                serde_json::Value::String(principal.to_text()),
            );
            map.insert(
                "method".to_string(),
                serde_json::Value::String(method.clone()),
            );
            serde_json::Value::Object(map)
        }
        IDLValue::Blob(bytes) => {
            // encode as base64 string
            let b64 = base64::engine::general_purpose::STANDARD.encode(bytes);
            serde_json::Value::String(format!("base64:{b64}"))
        }
    }
}

fn idl_args_to_json(args: &IDLArgs) -> serde_json::Value {
    let values: &Vec<IDLValue> = &args.args;
    match values.len() {
        0 => serde_json::Value::Null,
        1 => idl_value_to_json(&values[0]),
        _ => serde_json::Value::Array(values.iter().map(idl_value_to_json).collect()),
    }
}

fn try_decode_with_types(
    canister_id: &str,
    method: &str,
    host: Option<&str>,
    out: &[u8],
) -> Option<serde_json::Value> {
    // Best-effort: fetch candid and decode with known return types to preserve field names
    let did = fetch_candid(canister_id, host).ok()?;
    let prog: IDLProg = did.parse::<IDLProg>().ok()?;
    let mut env = TypeEnv::new();
    let actor_opt = check_prog(&mut env, &prog).ok()?;
    let actor = actor_opt?;
    let svc = env.as_service(&actor).ok()?;
    for (name, ty) in svc.iter() {
        if name == method {
            if let TypeInner::Func(f) = ty.as_ref() {
                // Decode with method return types
                if let Ok(args) = IDLArgs::from_bytes_with_types(out, &env, &f.rets) {
                    return Some(idl_args_to_json(&args));
                }
            }
        }
    }
    None
}

pub fn parse_candid_interface(candid_source: &str) -> Result<ParsedInterface, CanisterClientError> {
    // Parse Candid using official parser and type checker
    let prog: IDLProg = candid_source
        .parse::<IDLProg>()
        .map_err(|e| CanisterClientError::CandidParse(format!("parse: {e}")))?;
    let mut env = TypeEnv::new();
    let actor = check_prog(&mut env, &prog)
        .map_err(|e| CanisterClientError::CandidParse(format!("typecheck: {e}")))?
        .ok_or_else(|| CanisterClientError::CandidParse("no service/actor found".into()))?;

    // Extract service/interface methods
    let svc = env
        .as_service(&actor)
        .map_err(|e| CanisterClientError::CandidParse(format!("service: {e}")))?;

    let mut methods: Vec<MethodInfo> = Vec::new();
    for (name, ty) in svc.iter() {
        if let TypeInner::Func(f) = ty.as_ref() {
            // Determine method kind
            let mut mk = MethodKind::Update;
            if f.modes.contains(&FuncMode::CompositeQuery) {
                mk = MethodKind::CompositeQuery;
            } else if f.modes.contains(&FuncMode::Query) {
                mk = MethodKind::Query;
            }

            // Collect arg and return type strings using Display
            let args: Vec<String> = f.args.iter().map(|t| t.to_string()).collect();
            let rets: Vec<String> = f.rets.iter().map(|t| t.to_string()).collect();

            methods.push(MethodInfo {
                name: name.to_string(),
                kind: mk,
                args,
                rets,
            });
        }
    }

    Ok(ParsedInterface { methods })
}

fn json_to_idl_value(
    v: &serde_json::Value,
    _env: &TypeEnv,
    ty: &Type,
) -> Result<IDLValue, CanisterClientError> {
    use candid::types::TypeInner::*;
    Ok(match ty.as_ref() {
        Null | Reserved | Empty => IDLValue::Null,
        Bool => IDLValue::Bool(
            v.as_bool()
                .ok_or_else(|| CanisterClientError::CandidParse("expected bool".into()))?,
        ),
        Text => IDLValue::Text(
            v.as_str()
                .ok_or_else(|| CanisterClientError::CandidParse("expected text".into()))?
                .to_string(),
        ),
        Nat => match v {
            serde_json::Value::Number(n) => {
                let u = n
                    .as_u64()
                    .ok_or_else(|| CanisterClientError::CandidParse("expected nat".into()))?;
                IDLValue::Nat(CandidNat::from(u))
            }
            serde_json::Value::String(s) => {
                let n = CandidNat::parse(s.as_bytes())
                    .map_err(|_| CanisterClientError::CandidParse("invalid nat".into()))?;
                IDLValue::Nat(n)
            }
            _ => return Err(CanisterClientError::CandidParse("invalid nat".into())),
        },
        Int => match v {
            serde_json::Value::Number(n) => {
                let i = n
                    .as_i64()
                    .ok_or_else(|| CanisterClientError::CandidParse("expected int".into()))?;
                IDLValue::Int(CandidInt::from(i))
            }
            serde_json::Value::String(s) => {
                let i = CandidInt::parse(s.as_bytes())
                    .map_err(|_| CanisterClientError::CandidParse("invalid int".into()))?;
                IDLValue::Int(i)
            }
            _ => return Err(CanisterClientError::CandidParse("invalid int".into())),
        },
        Nat8 => IDLValue::Nat8(
            v.as_u64()
                .ok_or_else(|| CanisterClientError::CandidParse("expected nat8".into()))?
                as u8,
        ),
        Nat16 => IDLValue::Nat16(
            v.as_u64()
                .ok_or_else(|| CanisterClientError::CandidParse("expected nat16".into()))?
                as u16,
        ),
        Nat32 => IDLValue::Nat32(
            v.as_u64()
                .ok_or_else(|| CanisterClientError::CandidParse("expected nat32".into()))?
                as u32,
        ),
        Nat64 => IDLValue::Nat64(
            v.as_u64()
                .ok_or_else(|| CanisterClientError::CandidParse("expected nat64".into()))?,
        ),
        Int8 => IDLValue::Int8(
            v.as_i64()
                .ok_or_else(|| CanisterClientError::CandidParse("expected int8".into()))?
                as i8,
        ),
        Int16 => IDLValue::Int16(
            v.as_i64()
                .ok_or_else(|| CanisterClientError::CandidParse("expected int16".into()))?
                as i16,
        ),
        Int32 => IDLValue::Int32(
            v.as_i64()
                .ok_or_else(|| CanisterClientError::CandidParse("expected int32".into()))?
                as i32,
        ),
        Int64 => IDLValue::Int64(
            v.as_i64()
                .ok_or_else(|| CanisterClientError::CandidParse("expected int64".into()))?,
        ),
        Float32 => IDLValue::Float32(
            v.as_f64()
                .ok_or_else(|| CanisterClientError::CandidParse("expected float32".into()))?
                as f32,
        ),
        Float64 => IDLValue::Float64(
            v.as_f64()
                .ok_or_else(|| CanisterClientError::CandidParse("expected float64".into()))?,
        ),
        Principal => {
            let s = v.as_str().ok_or_else(|| {
                CanisterClientError::CandidParse("expected principal text".into())
            })?;
            let p = CanisterPrincipal::from_text(s)
                .map_err(|_| CanisterClientError::CandidParse("invalid principal".into()))?;
            IDLValue::Principal(p)
        }
        Opt(inner) => {
            if v.is_null() {
                IDLValue::None
            } else {
                IDLValue::Opt(Box::new(json_to_idl_value(v, _env, inner)?))
            }
        }
        Vec(inner) => {
            let arr = v
                .as_array()
                .ok_or_else(|| CanisterClientError::CandidParse("expected array".into()))?;
            let vals = arr
                .iter()
                .map(|x| json_to_idl_value(x, _env, inner))
                .collect::<Result<StdVec<_>, _>>()?;
            IDLValue::Vec(vals)
        }
        Record(fs) => {
            let mut out: StdVec<IDLField> = StdVec::new();
            match v {
                serde_json::Value::Object(map) => {
                    for Field { id, ty: fty } in fs {
                        let key = label_to_string(id);
                        if let Some(vv) = map.get(&key) {
                            out.push(IDLField {
                                id: id.as_ref().clone(),
                                val: json_to_idl_value(vv, _env, fty)?,
                            });
                        } else {
                            use candid::types::TypeInner as TI;
                            match fty.as_ref() {
                                TI::Opt(_) => out.push(IDLField {
                                    id: id.as_ref().clone(),
                                    val: IDLValue::None,
                                }),
                                _ => {
                                    return Err(CanisterClientError::CandidParse(format!(
                                        "missing field {key}"
                                    )))
                                }
                            }
                        }
                    }
                }
                serde_json::Value::Array(arr) => {
                    if arr.len() != fs.len() {
                        return Err(CanisterClientError::CandidParse(
                            "record arity mismatch".into(),
                        ));
                    }
                    for (i, Field { id, ty: fty }) in fs.iter().enumerate() {
                        out.push(IDLField {
                            id: id.as_ref().clone(),
                            val: json_to_idl_value(&arr[i], _env, fty)?,
                        });
                    }
                }
                _ => {
                    return Err(CanisterClientError::CandidParse(
                        "expected object/array for record".into(),
                    ))
                }
            }
            IDLValue::Record(out)
        }
        // Support variants as { "Case": value }
        Variant(variants) => {
            let obj = v.as_object().ok_or_else(|| {
                CanisterClientError::CandidParse(
                    "expected object for variant: { \"Case\": value }".into(),
                )
            })?;
            if obj.len() != 1 {
                return Err(CanisterClientError::CandidParse(
                    "variant expects exactly one case".into(),
                ));
            }
            let (case_key, case_val) = obj.iter().next().unwrap();
            let mut found: Option<(usize, Field)> = None;
            for (idx, field) in variants.iter().enumerate() {
                if label_to_string(&field.id) == *case_key {
                    found = Some((
                        idx,
                        Field {
                            id: field.id.clone(),
                            ty: field.ty.clone(),
                        },
                    ));
                    break;
                }
            }
            let (idx, Field { id, ty }) = found.ok_or_else(|| {
                CanisterClientError::CandidParse(format!("unknown variant case {case_key}"))
            })?;
            use candid::types::TypeInner as TI;
            let payload = match ty.as_ref() {
                TI::Null | TI::Reserved | TI::Empty => IDLValue::Null,
                _ => json_to_idl_value(case_val, _env, &ty)?,
            };
            let fld = IDLField {
                id: id.as_ref().clone(),
                val: payload,
            };
            IDLValue::Variant(VariantValue(Box::new(fld), idx as u64))
        }
        // Functions and services remain unsupported for JSON mapping
        Func(_) | Service(_) => {
            return Err(CanisterClientError::CandidParse(format!(
                "unsupported candid type in JSON args: {ty}"
            )))
        }
        Unknown | Knot(_) | Class(_, _) | Future => {
            return Err(CanisterClientError::CandidParse(format!(
                "unsupported candid type in JSON args: {ty}"
            )))
        }
        Var(_id) => {
            // Type variables are not resolved here; treat as unsupported to fail fast
            return Err(CanisterClientError::CandidParse(format!(
                "unsupported candid type in JSON args: {ty}"
            )));
        }
    })
}

fn build_args_from_json(
    canister_id: &str,
    method: &str,
    host: Option<&str>,
    json_args: &str,
) -> Result<Vec<u8>, CanisterClientError> {
    // Fetch candid and locate method arg types
    let did = fetch_candid(canister_id, host)?;
    let prog: IDLProg = did
        .parse::<IDLProg>()
        .map_err(|e| CanisterClientError::CandidParse(format!("parse: {e}")))?;
    let mut env = TypeEnv::new();
    let actor = check_prog(&mut env, &prog)
        .map_err(|e| CanisterClientError::CandidParse(format!("typecheck: {e}")))?
        .ok_or_else(|| CanisterClientError::CandidParse("no service/actor found".into()))?;
    let svc = env
        .as_service(&actor)
        .map_err(|e| CanisterClientError::CandidParse(format!("service: {e}")))?;
    let mut arg_tys: Option<Vec<Type>> = None;
    for (name, ty) in svc.iter() {
        if name == method {
            if let TypeInner::Func(f) = ty.as_ref() {
                arg_tys = Some(f.args.clone());
            }
            break;
        }
    }
    let arg_tys =
        arg_tys.ok_or_else(|| CanisterClientError::CandidParse("method not found".into()))?;

    let parsed_json: serde_json::Value = if json_args.trim().is_empty() {
        serde_json::Value::Null
    } else {
        serde_json::from_str(json_args)
            .map_err(|e| CanisterClientError::CandidParse(format!("json parse: {e}")))?
    };

    let values: Vec<IDLValue> = if arg_tys.is_empty() {
        Vec::new()
    } else if arg_tys.len() == 1 {
        let v = json_to_idl_value(&parsed_json, &env, &arg_tys[0])?;
        vec![v]
    } else {
        let arr = parsed_json.as_array().ok_or_else(|| {
            CanisterClientError::CandidParse("expected JSON array for multiple args".into())
        })?;
        if arr.len() != arg_tys.len() {
            return Err(CanisterClientError::CandidParse(format!(
                "args arity mismatch: expected {}, got {}",
                arg_tys.len(),
                arr.len()
            )));
        }
        let mut vs = Vec::with_capacity(arg_tys.len());
        for (i, t) in arg_tys.iter().enumerate() {
            vs.push(json_to_idl_value(&arr[i], &env, t).map_err(|e| {
                CanisterClientError::CandidParse(format!(
                    "arg {} decode failed for type {}: {}",
                    i, t, e
                ))
            })?);
        }
        vs
    };
    IDLArgs::new(&values)
        .to_bytes()
        .map_err(|e| CanisterClientError::CandidParse(format!("encode args: {e}")))
}

fn parse_idl_args_bytes(arg_candid: &str) -> Result<Vec<u8>, CanisterClientError> {
    let s = arg_candid.trim();
    if s.is_empty() || s == "()" {
        return IDLArgs::new(&[])
            .to_bytes()
            .map_err(|e| CanisterClientError::CandidParse(format!("encode empty args: {e}")));
    }
    if let Some(rest) = s.strip_prefix("base64:") {
        use base64::Engine as _;
        let bytes = base64::engine::general_purpose::STANDARD
            .decode(rest)
            .map_err(|e| CanisterClientError::CandidParse(format!("base64 args decode: {e}")))?;
        return Ok(bytes);
    }
    // Try to parse textual Candid args using candid_parser, e.g. "(42, \"hello\")"
    match candid_parser::parse_idl_args(s) {
        Ok(vargs) => vargs
            .to_bytes()
            .map_err(|e| CanisterClientError::CandidParse(format!("encode args: {e}"))),
        Err(e) => Err(CanisterClientError::CandidParse(format!("args parse: {e}"))),
    }
}

fn parse_principal(canister_id: &str) -> Result<Principal, CanisterClientError> {
    Principal::from_text(canister_id)
        .map_err(|_| CanisterClientError::InvalidCanisterId(canister_id.to_string()))
}

pub fn fetch_candid(canister_id: &str, host: Option<&str>) -> Result<String, CanisterClientError> {
    use ic_agent::Agent;

    let canister = parse_principal(canister_id)?;
    let host = host.unwrap_or("https://ic0.app");

    let agent = Agent::builder()
        .with_url(host)
        .build()
        .map_err(|e| CanisterClientError::Net(format!("build agent: {e}")))?;

    let fut = async {
        // Ensure root key is fetched before making certified requests.
        agent.fetch_root_key().await?;
        // Use certified canister metadata for `candid:service`.
        agent
            .read_state_canister_metadata(canister, "candid:service")
            .await
    };
    let rt =
        tokio::runtime::Runtime::new().map_err(|e| CanisterClientError::Net(format!("rt: {e}")))?;
    let bytes = rt
        .block_on(fut)
        .map_err(|e| CanisterClientError::Net(format!("read_state: {e}")))?;

    let candid_text =
        String::from_utf8(bytes).map_err(|e| CanisterClientError::Net(format!("utf8: {e}")))?;
    Ok(candid_text)
}

pub fn call_anonymous(
    canister_id: &str,
    method: &str,
    kind: MethodKind,
    arg_candid: &str,
    host: Option<&str>,
) -> Result<String, CanisterClientError> {
    use ic_agent::Agent;

    let canister = Principal::from_text(canister_id)
        .map_err(|_| CanisterClientError::InvalidCanisterId(canister_id.to_string()))?;
    let host_url = host.unwrap_or("https://ic0.app");
    let agent = Agent::builder()
        .with_url(host_url)
        .build()
        .map_err(|e| CanisterClientError::Net(format!("build agent: {e}")))?;
    // Accept either textual candid or JSON (when starts with '[' or '{' or 'null' or scalar JSON)
    let arg_bytes = if arg_candid.trim_start().starts_with('[')
        || arg_candid.trim_start().starts_with('{')
        || arg_candid.trim_start().starts_with('n')
        || arg_candid.trim_start().starts_with('"')
        || arg_candid.trim_start().starts_with('t')
        || arg_candid.trim_start().starts_with('f')
        || arg_candid
            .trim_start()
            .chars()
            .next()
            .map(|c| c.is_ascii_digit() || c == '-')
            .unwrap_or(false)
    {
        build_args_from_json(canister_id, method, host, arg_candid)?
    } else {
        parse_idl_args_bytes(arg_candid)?
    };

    let fut = async {
        // Ensure root key is fetched before making certified requests.
        agent.fetch_root_key().await?;
        match kind {
            MethodKind::Query | MethodKind::CompositeQuery => {
                agent
                    .query(&canister, method)
                    .with_arg(arg_bytes)
                    .call()
                    .await
            }
            MethodKind::Update => {
                agent
                    .update(&canister, method)
                    .with_arg(arg_bytes)
                    .call_and_wait()
                    .await
            }
        }
    };
    let rt =
        tokio::runtime::Runtime::new().map_err(|e| CanisterClientError::Net(format!("rt: {e}")))?;
    let out = rt
        .block_on(fut)
        .map_err(|e| CanisterClientError::Net(format!("call: {e}")))?;
    let json_value = try_decode_with_types(canister_id, method, host, &out)
        .or_else(|| {
            IDLArgs::from_bytes(&out)
                .ok()
                .map(|args| idl_args_to_json(&args))
        })
        .ok_or_else(|| CanisterClientError::CandidParse("decode failed".into()))?;
    let response = json!({
        "ok": true,
        "result": json_value,
    });
    Ok(response.to_string())
}

pub fn call_authenticated(
    canister_id: &str,
    method: &str,
    kind: MethodKind,
    arg_candid: &str,
    ed25519_private_key_b64: &str,
    host: Option<&str>,
) -> Result<String, CanisterClientError> {
    use base64::Engine;
    use ic_agent::{identity::BasicIdentity, Agent};

    let canister = Principal::from_text(canister_id)
        .map_err(|_| CanisterClientError::InvalidCanisterId(canister_id.to_string()))?;
    let host_url = host.unwrap_or("https://ic0.app");

    let priv_bytes = base64::engine::general_purpose::STANDARD
        .decode(ed25519_private_key_b64)
        .map_err(|e| CanisterClientError::Net(format!("b64 decode: {e}")))?;
    let key: [u8; 32] = priv_bytes
        .try_into()
        .map_err(|_| CanisterClientError::Net("invalid ed25519 key length".into()))?;
    let identity = BasicIdentity::from_raw_key(&key);

    let agent = Agent::builder()
        .with_url(host_url)
        .with_identity(identity)
        .build()
        .map_err(|e| CanisterClientError::Net(format!("build agent: {e}")))?;

    let arg_bytes = if arg_candid.trim_start().starts_with('[')
        || arg_candid.trim_start().starts_with('{')
        || arg_candid.trim_start().starts_with('n')
        || arg_candid.trim_start().starts_with('"')
        || arg_candid.trim_start().starts_with('t')
        || arg_candid.trim_start().starts_with('f')
        || arg_candid
            .trim_start()
            .chars()
            .next()
            .map(|c| c.is_ascii_digit() || c == '-')
            .unwrap_or(false)
    {
        build_args_from_json(canister_id, method, host, arg_candid)?
    } else {
        parse_idl_args_bytes(arg_candid)?
    };
    let fut = async {
        // Ensure root key is fetched before making certified requests.
        agent.fetch_root_key().await?;
        match kind {
            MethodKind::Query | MethodKind::CompositeQuery => {
                agent
                    .query(&canister, method)
                    .with_arg(arg_bytes)
                    .call()
                    .await
            }
            MethodKind::Update => {
                agent
                    .update(&canister, method)
                    .with_arg(arg_bytes)
                    .call_and_wait()
                    .await
            }
        }
    };
    let rt =
        tokio::runtime::Runtime::new().map_err(|e| CanisterClientError::Net(format!("rt: {e}")))?;
    let out = rt
        .block_on(fut)
        .map_err(|e| CanisterClientError::Net(format!("call: {e}")))?;
    let json_value = try_decode_with_types(canister_id, method, host, &out)
        .or_else(|| {
            IDLArgs::from_bytes(&out)
                .ok()
                .map(|args| idl_args_to_json(&args))
        })
        .ok_or_else(|| CanisterClientError::CandidParse("decode failed".into()))?;
    let response = json!({
        "ok": true,
        "result": json_value,
    });
    Ok(response.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_args_empty_and_textual() {
        // Empty
        let b = parse_idl_args_bytes("()").expect("empty args ok");
        let args = IDLArgs::from_bytes(&b).expect("decode empty");
        assert_eq!(args.to_string(), "()");

        // Single nat and text
        let b = parse_idl_args_bytes("(42, \"hi\")").expect("textual args ok");
        let args = IDLArgs::from_bytes(&b).expect("decode textual");
        // Parser may annotate default number types; accept either annotated or unannotated form
        let s = args.to_string();
        assert!(s == "(42, \"hi\")" || s == "(42 : int, \"hi\")", "got {s}");
    }

    #[test]
    fn idl_value_json_basic_shapes() {
        // Empty -> null
        let args = IDLArgs::new(&[]);
        assert_eq!(idl_args_to_json(&args), serde_json::Value::Null);

        // Single scalar -> unwrapped
        let args = IDLArgs::new(&[IDLValue::Bool(true)]);
        assert_eq!(idl_args_to_json(&args), serde_json::Value::Bool(true));

        // Tuple -> array
        let args = IDLArgs::new(&[IDLValue::Text("a".into()), IDLValue::Nat8(5)]);
        assert_eq!(idl_args_to_json(&args), serde_json::json!(["a", 5]));

        // Record with named and numeric fields
        let rec = IDLValue::Record(vec![
            IDLField {
                id: Label::Named("ticker".into()),
                val: IDLValue::Text("ICP".into()),
            },
            IDLField {
                id: Label::Id(4007505752),
                val: IDLValue::Text("ICP".into()),
            },
        ]);
        let args = IDLArgs::new(&[rec]);
        let v = idl_args_to_json(&args);
        assert!(v.is_object());
        let obj = v.as_object().unwrap();
        assert!(obj.contains_key("ticker") || obj.contains_key("4007505752"));
    }
}
