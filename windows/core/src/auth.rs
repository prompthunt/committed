use super::*;
const CLIENT_ID: &str = "Ov23lij4oZbEeMZk3889";

#[derive(Clone, Serialize)]
pub struct DevicePrompt {
    pub user_code: String,
    pub verification_uri: String,
    pub interval: i64,
}
#[derive(Clone)]
pub(crate) struct DeviceAttempt {
    code: String,
    deadline: i64,
    interval: i64,
    next_poll: i64,
    failures: u32,
}
#[derive(Debug, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ConnectStatus {
    Pending,
    SlowDown,
    Connected,
}
#[derive(Deserialize)]
struct DeviceResponse {
    device_code: String,
    user_code: String,
    verification_uri: String,
    expires_in: i64,
    interval: i64,
}
impl BoardCore {
    pub async fn start_connect(&self) -> Result<DevicePrompt, String> {
        let generation = {
            let mut state = self.state.lock().unwrap();
            state.generation += 1;
            state.device = None;
            state.polling = false;
            state.generation
        };
        let text = self
            .http
            .request(Request {
                url: "https://github.com/login/device/code".into(),
                token: None,
                form: Some(vec![
                    ("client_id".into(), CLIENT_ID.into()),
                    ("scope".into(), "read:org read:user".into()),
                ]),
            })
            .await?;
        let response: DeviceResponse =
            serde_json::from_str(&text).map_err(|_| "GitHub did not return a connection code")?;
        if response.verification_uri != "https://github.com/login/device" {
            return Err("Unexpected GitHub verification address".into());
        }
        let now = self.clock.now();
        let interval = response.interval.clamp(1, 60);
        let mut state = self.state.lock().unwrap();
        if state.generation != generation {
            return Err("Connection cancelled. Try again.".into());
        }
        state.device = Some(DeviceAttempt {
            code: response.device_code,
            deadline: now + response.expires_in.clamp(1, 1800),
            interval,
            next_poll: now + interval,
            failures: 0,
        });
        Ok(DevicePrompt {
            user_code: response.user_code,
            verification_uri: response.verification_uri,
            interval,
        })
    }
    pub async fn poll_connect(&self) -> Result<ConnectStatus, String> {
        let (attempt, generation) = {
            let mut state = self.state.lock().unwrap();
            let Some(attempt) = state.device.as_ref() else {
                return Err("Connect GitHub to get a new code.".into());
            };
            if self.clock.now() >= attempt.deadline {
                state.device = None;
                return Err("Your code expired. Connect GitHub to try again.".into());
            }
            if state.polling || self.clock.now() < attempt.next_poll {
                return Ok(ConnectStatus::Pending);
            }
            let attempt = attempt.clone();
            state.polling = true;
            (attempt, state.generation)
        };
        let response = self
            .http
            .request(Request {
                url: "https://github.com/login/oauth/access_token".into(),
                token: None,
                form: Some(vec![
                    ("client_id".into(), CLIENT_ID.into()),
                    ("device_code".into(), attempt.code.clone()),
                    (
                        "grant_type".into(),
                        "urn:ietf:params:oauth:grant-type:device_code".into(),
                    ),
                ]),
            })
            .await;
        let payload: Result<serde_json::Value, String> = response.and_then(|text| {
            serde_json::from_str(&text).map_err(|_| "Invalid connection response".into())
        });
        // Resolve the owner before accepting the token; no credential reaches the UI.
        let owner = if let Ok(value) = &payload {
            if let Some(token) = value["access_token"].as_str() {
                Some(
                    self.http
                        .request(Request {
                            url: "https://api.github.com/user".into(),
                            token: Some(token.into()),
                            form: None,
                        })
                        .await
                        .and_then(|text| {
                            serde_json::from_str::<Person>(&text)
                                .map_err(|_| "Could not read GitHub profile".into())
                        }),
                )
            } else {
                None
            }
        } else {
            None
        };
        let mut state = self.state.lock().unwrap();
        if state.generation != generation {
            return Err("Connection cancelled. Try again.".into());
        }
        state.polling = false;
        let current = state.device.as_mut().ok_or("Connection cancelled")?;
        current.next_poll = self.clock.now() + current.interval;
        let value = match payload {
            Ok(value) => {
                current.failures = 0;
                value
            }
            Err(_) => {
                current.failures += 1;
                if current.failures < 3 {
                    return Ok(ConnectStatus::Pending);
                }
                state.device = None;
                return Err("Could not reach GitHub. Connect GitHub to try again.".into());
            }
        };
        if let Some(token) = value["access_token"].as_str() {
            let mut owner = owner.ok_or("Missing GitHub profile")??;
            owner.login = owner.login.to_ascii_lowercase();
            if !valid_login(&owner.login) {
                return Err("Invalid GitHub profile".into());
            }
            self.credentials.set(Some(token))?;
            if state.saved.owner.as_ref() != Some(&owner.login) {
                state.saved.counts.clear();
                state.saved.people.clear();
            }
            state.saved.owner = Some(owner.login.clone());
            if !state.saved.people.iter().any(|p| p.login == owner.login) {
                state.saved.people.insert(0, owner);
            }
            state.device = None;
            self.persist(&state)?;
            return Ok(ConnectStatus::Connected);
        }
        match value["error"].as_str() {
            Some("authorization_pending") => Ok(ConnectStatus::Pending),
            Some("slow_down") => {
                current.interval = (current.interval + 5).min(60);
                current.next_poll = self.clock.now() + current.interval;
                Ok(ConnectStatus::SlowDown)
            }
            other => {
                state.device = None;
                Err(match other {
                    Some("access_denied") => "Access was denied. Connect GitHub to try again.",
                    Some("expired_token") => "Your code expired. Connect GitHub to try again.",
                    _ => "GitHub could not connect. Please try again.",
                }
                .into())
            }
        }
    }
}
