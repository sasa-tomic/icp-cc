use candid::{IDLArgs, Principal};
use regex::Regex;
use serde::{Deserialize, Serialize};
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
    let service_split = candid_source
        .split("service ")
        .nth(1)
        .ok_or_else(|| CanisterClientError::CandidParse("missing service block".into()))?;

    let mut methods: Vec<MethodInfo> = Vec::new();

    let re = Regex::new(r"(?m)^\s*([a-zA-Z_][\w-]*)\s*:\s*\(([^)]*)\)\s*->\s*\(([^)]*)\)\s*(?:query|composite_query)?").unwrap();
    for cap in re.captures_iter(service_split) {
        let name = cap.get(1).unwrap().as_str().to_string();
        let args_str = cap.get(2).unwrap().as_str().trim();
        let rets_str = cap.get(3).unwrap().as_str().trim();

        // Find suffix on the matched line
        let matched = cap.get(0).unwrap().as_str();
        let kind = if matched.contains("composite_query") {
            MethodKind::CompositeQuery
        } else if matched.contains("query") {
            MethodKind::Query
        } else {
            MethodKind::Update
        };

        let args = if args_str.is_empty() {
            vec![]
        } else {
            args_str.split(',').map(|s| s.trim().to_string()).collect()
        };
        let rets = if rets_str.is_empty() {
            vec![]
        } else {
            rets_str.split(',').map(|s| s.trim().to_string()).collect()
        };

        methods.push(MethodInfo {
            name,
            kind,
            args,
            rets,
        });
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
    Err(CanisterClientError::CandidParse(
        "only empty () or base64:<blob> supported for args".into(),
    ))
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
    Ok(decoded.to_string())
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
    Ok(decoded.to_string())
}
