//! The public board boundary; platform adapters live in the desktop crate.
mod auth;
mod movement;
mod parser;
mod refresh;
use async_trait::async_trait;
pub use auth::{ConnectStatus, DevicePrompt};
use chrono::NaiveDate;
pub use refresh::{PeopleFilter, PersonVisibility, RefreshReason};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::sync::{Arc, Mutex};

pub struct Request {
    pub url: String,
    pub token: Option<String>,
    pub form: Option<Vec<(String, String)>>,
}
#[async_trait]
pub trait Http: Send + Sync {
    async fn request(&self, request: Request) -> Result<String, String>;
}
pub trait Clock: Send + Sync {
    fn now(&self) -> i64;
    fn today(&self) -> NaiveDate;
}
pub trait Storage: Send + Sync {
    fn load(&self) -> Result<Option<String>, String>;
    fn save(&self, value: &str) -> Result<(), String>;
}
pub trait CredentialStore: Send + Sync {
    fn get(&self) -> Result<Option<String>, String>;
    fn set(&self, token: Option<&str>) -> Result<(), String>;
}
#[derive(Clone, Debug, Serialize, PartialEq)]
pub struct Notification {
    pub title: String,
    pub body: String,
}
pub trait Notifier: Send + Sync {
    fn post(&self, notification: Notification);
}

#[derive(Clone, Copy, Debug, Default, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "camelCase")]
pub enum Window {
    #[default]
    Today,
    Week,
    Month,
}
impl Window {
    fn days(self) -> i64 {
        match self {
            Self::Today => 1,
            Self::Week => 7,
            Self::Month => 30,
        }
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Person {
    pub login: String,
    pub name: Option<String>,
    pub avatar_url: Option<String>,
    #[serde(default)]
    pub following: bool,
    #[serde(default)]
    pub organizations: Vec<String>,
}
impl Person {
    fn username(login: &str) -> Self {
        Self {
            login: login.into(),
            name: None,
            avatar_url: None,
            following: false,
            organizations: vec![],
        }
    }
}
#[derive(Clone, Debug, Serialize)]
pub struct Row {
    #[serde(flatten)]
    pub person: Person,
    pub rank: usize,
    pub contributions: Option<u32>,
    pub is_you: bool,
    pub movement: i32,
    pub status: String,
}
#[derive(Clone, Debug, Serialize)]
pub struct Board {
    pub window: Window,
    pub rows: Vec<Row>,
    pub owner: Option<String>,
    pub refreshing: bool,
    pub last_updated: Option<i64>,
    pub error: Option<String>,
    pub people_updated: Option<i64>,
    pub people_error: Option<String>,
}
#[derive(Clone, Default, Serialize, Deserialize)]
struct Snapshot {
    days: BTreeMap<NaiveDate, u32>,
    updated: i64,
}
#[derive(Default, Serialize, Deserialize)]
struct Saved {
    owner: Option<String>,
    people: Vec<Person>,
    counts: BTreeMap<String, Snapshot>,
    #[serde(default)]
    people_updated: Option<i64>,
    #[serde(default)]
    hidden: BTreeMap<String, BTreeSet<String>>,
    #[serde(default)]
    settings: Settings,
}
#[derive(Clone, Serialize, Deserialize)]
pub struct Settings {
    pub notifications: bool,
    pub automatic_updates: bool,
    pub private_tip_dismissed: bool,
}
impl Default for Settings {
    fn default() -> Self {
        Self {
            notifications: false,
            automatic_updates: true,
            private_tip_dismissed: false,
        }
    }
}
impl Saved {
    fn hidden(&self, login: &str) -> bool {
        self.owner
            .as_ref()
            .and_then(|o| self.hidden.get(o))
            .is_some_and(|h| h.contains(login))
    }
}
#[derive(Default)]
struct State {
    saved: Saved,
    refreshing: bool,
    error: Option<String>,
    generation: u64,
    device: Option<auth::DeviceAttempt>,
    polling: bool,
    people_error: Option<String>,
    people_attempt: Option<i64>,
    failed: BTreeMap<String, String>,
    selected: Window,
    baseline: Option<(NaiveDate, BTreeMap<String, usize>)>,
    previous: BTreeMap<Window, (NaiveDate, BTreeMap<String, u32>)>,
}
pub struct BoardCore {
    http: Arc<dyn Http>,
    clock: Arc<dyn Clock>,
    storage: Arc<dyn Storage>,
    credentials: Arc<dyn CredentialStore>,
    notifier: Arc<dyn Notifier>,
    state: Mutex<State>,
}
impl BoardCore {
    pub fn new(
        http: Arc<dyn Http>,
        clock: Arc<dyn Clock>,
        storage: Arc<dyn Storage>,
        credentials: Arc<dyn CredentialStore>,
        notifier: Arc<dyn Notifier>,
    ) -> Result<Self, String> {
        let saved = storage
            .load()?
            .map(|text| {
                serde_json::from_str(&text).map_err(|_| "Saved board could not be read".to_string())
            })
            .transpose()?
            .unwrap_or_default();
        Ok(Self {
            http,
            clock,
            storage,
            credentials,
            notifier,
            state: Mutex::new(State {
                saved,
                ..State::default()
            }),
        })
    }
    pub fn board(&self, window: Window) -> Board {
        let state = self.state.lock().unwrap();
        let today = self.clock.today();
        let rows = ranked_rows(&state, window, today);
        Board {
            window,
            rows,
            owner: state.saved.owner.clone(),
            refreshing: state.refreshing,
            last_updated: state
                .saved
                .people
                .iter()
                .filter(|p| !state.saved.hidden(&p.login))
                .filter_map(|p| state.saved.counts.get(&p.login).map(|s| s.updated))
                .min(),
            error: state.error.clone(),
            people_updated: state.saved.people_updated,
            people_error: state.people_error.clone(),
        }
    }
    pub fn select_window(&self, window: Window) {
        self.state.lock().unwrap().selected = window;
    }
    pub async fn preview(&self, login: &str) -> Result<(), String> {
        if !valid_login(login) {
            return Err("Invalid GitHub username".into());
        }
        let html = self
            .http
            .request(Request {
                url: format!("https://github.com/users/{login}/contributions"),
                token: None,
                form: None,
            })
            .await?;
        let days = parser::parse(&html)?;
        let mut state = self.state.lock().unwrap();
        state.saved.people = vec![Person::username(login)];
        state.saved.counts.insert(
            login.into(),
            Snapshot {
                days,
                updated: self.clock.now(),
            },
        );
        Ok(())
    }
    fn persist(&self, state: &State) -> Result<(), String> {
        self.storage
            .save(&serde_json::to_string(&state.saved).map_err(|e| e.to_string())?)
    }
    pub fn connected(&self) -> Result<bool, String> {
        Ok(self.credentials.get()?.is_some())
    }
    pub fn settings(&self) -> Settings {
        self.state.lock().unwrap().saved.settings.clone()
    }
    pub fn set_setting(&self, setting: &str, enabled: bool) -> Result<(), String> {
        let mut state = self.state.lock().unwrap();
        match setting {
            "notifications" => state.saved.settings.notifications = enabled,
            "automatic_updates" => state.saved.settings.automatic_updates = enabled,
            "private_tip_dismissed" => state.saved.settings.private_tip_dismissed = enabled,
            _ => return Err("Unknown setting".into()),
        }
        self.persist(&state)
    }
    pub fn set_hidden(&self, login: &str, hidden: bool) -> Result<(), String> {
        let login = login.to_ascii_lowercase();
        let mut state = self.state.lock().unwrap();
        let owner = state.saved.owner.clone().ok_or("Connect GitHub first")?;
        if login == owner {
            return Err("Your own standing is always visible".into());
        }
        if !state.saved.people.iter().any(|p| p.login == login) {
            return Err("Person is not in your People list".into());
        }
        let list = state.saved.hidden.entry(owner).or_default();
        if hidden {
            list.insert(login);
        } else {
            list.remove(&login);
        }
        state.generation += 1;
        state.refreshing = false;
        state.baseline = None;
        state.previous.clear();
        self.persist(&state)
    }
    pub fn disconnect(&self) -> Result<(), String> {
        let mut state = self.state.lock().unwrap();
        self.credentials.set(None)?;
        state.generation += 1;
        state.device = None;
        state.polling = false;
        state.saved.owner = None;
        state.saved.people.clear();
        state.saved.counts.clear();
        state.refreshing = false;
        state.error = None;
        state.people_error = None;
        state.people_attempt = None;
        state.saved.people_updated = None;
        state.failed.clear();
        state.baseline = None;
        state.previous.clear();
        self.persist(&state)
    }
}
fn ranked_rows(state: &State, window: Window, today: NaiveDate) -> Vec<Row> {
    let mut rows: Vec<_> = state
        .saved
        .people
        .iter()
        .filter(|p| !state.saved.hidden(&p.login))
        .map(|person| {
            let snapshot = state.saved.counts.get(&person.login);
            Row {
                person: person.clone(),
                rank: 0,
                contributions: snapshot.map(|s| parser::sum(&s.days, window.days(), today)),
                is_you: state.saved.owner.as_ref() == Some(&person.login),
                movement: 0,
                status: if state.failed.contains_key(&person.login) {
                    "failed"
                } else if state.refreshing {
                    "loading"
                } else if snapshot.is_some() {
                    "loaded"
                } else {
                    "missing"
                }
                .into(),
            }
        })
        .collect();
    rows.sort_by_key(|row| std::cmp::Reverse(row.contributions));
    for (index, row) in rows.iter_mut().enumerate() {
        row.rank = index + 1;
        if window == Window::Today
            && row.contributions.is_some()
            && !state.failed.contains_key(&row.person.login)
        {
            row.movement = state
                .baseline
                .as_ref()
                .filter(|(day, _)| *day == today)
                .and_then(|(_, ranks)| ranks.get(&row.person.login))
                .map(|rank| *rank as i32 - row.rank as i32)
                .unwrap_or(0);
        }
    }
    rows
}
fn valid_login(login: &str) -> bool {
    !login.is_empty()
        && login.len() <= 39
        && login
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || c == b'-')
}
