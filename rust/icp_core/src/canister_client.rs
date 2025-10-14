use candid::types::{FuncMode, TypeEnv, TypeInner};
use candid::{IDLArgs, Principal};
use candid_parser::{check_prog, IDLProg};
use serde::{Deserialize, Serialize};
use serde_json::json;
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
    let host = host.unwrap_or("https://ic0.app");
    let agent = Agent::builder()
        .with_url(host)
        .build()
        .map_err(|e| CanisterClientError::Net(format!("build agent: {e}")))?;
    let arg_bytes = parse_idl_args_bytes(arg_candid)?;

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
    let decoded = IDLArgs::from_bytes(&out)
        .map_err(|e| CanisterClientError::CandidParse(format!("decode: {e}")))?;
    let candid_text = decoded.to_string();
    let response = json!({
        "ok": true,
        "result_candid": candid_text,
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
    let host = host.unwrap_or("https://ic0.app");

    let priv_bytes = base64::engine::general_purpose::STANDARD
        .decode(ed25519_private_key_b64)
        .map_err(|e| CanisterClientError::Net(format!("b64 decode: {e}")))?;
    let key: [u8; 32] = priv_bytes
        .try_into()
        .map_err(|_| CanisterClientError::Net("invalid ed25519 key length".into()))?;
    let identity = BasicIdentity::from_raw_key(&key);

    let agent = Agent::builder()
        .with_url(host)
        .with_identity(identity)
        .build()
        .map_err(|e| CanisterClientError::Net(format!("build agent: {e}")))?;

    let arg_bytes = parse_idl_args_bytes(arg_candid)?;
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
    let decoded = IDLArgs::from_bytes(&out)
        .map_err(|e| CanisterClientError::CandidParse(format!("decode: {e}")))?;
    let candid_text = decoded.to_string();
    let response = json!({
        "ok": true,
        "result_candid": candid_text,
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
}
