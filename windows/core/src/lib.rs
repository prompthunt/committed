//! The public board boundary; platform adapters live in the desktop crate.
mod auth;
pub mod history;
mod movement;
mod parser;
mod refresh;
use async_trait::async_trait;
pub use auth::{ConnectStatus, DevicePrompt};
use chrono::{Datelike, NaiveDate};
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

/// A board's time range. `Monthly` (30 days) serializes as Swift's and the relay's raw value,
/// `"monthly"`, so every platform means the same thing by it.
#[derive(Clone, Copy, Debug, Default, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "camelCase")]
pub enum Window {
    #[default]
    Today,
    Week,
    /// The last 30 days, including today.
    #[serde(rename = "monthly")]
    Monthly,
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
// GitHub's `following` is a numeric profile statistic. Source membership is
// local board state, so API payloads must not deserialize into Person directly.
#[derive(Deserialize)]
struct GitHubPerson {
    login: String,
    name: Option<String>,
    avatar_url: Option<String>,
}
impl TryFrom<GitHubPerson> for Person {
    type Error = String;
    fn try_from(profile: GitHubPerson) -> Result<Self, String> {
        let login = profile.login.to_ascii_lowercase();
        if !valid_login(&login) {
            return Err("Invalid GitHub username".into());
        }
        Ok(Self {
            login,
            name: profile.name,
            avatar_url: profile.avatar_url,
            following: false,
            organizations: vec![],
        })
    }
}
#[derive(Clone, Debug, Serialize)]
pub struct Row {
    #[serde(flatten)]
    pub person: Person,
    pub rank: usize,
    pub contributions: Option<u32>,
    /// Consecutive days with a contribution, alive through today (`history::current_streak`).
    /// `None` when this person's calendar hasn't loaded, never 0 for missing data.
    pub streak: Option<u32>,
    pub is_you: bool,
    pub movement: i32,
    pub status: String,
    /// The window's trolling day, if any: the row wears the troll face. Ranking ignores it.
    pub burst: Option<parser::Burst>,
}
/// One person's view (`BoardCore::person`): their month day by day beside last month, streaks
/// and active days. The same content as the Mac and iPhone person views.
#[derive(Clone, Debug, Serialize)]
pub struct PersonView {
    #[serde(flatten)]
    pub person: Person,
    pub is_you: bool,
    /// The board row's status for this person ("loaded", "cached", "failed", …).
    pub status: String,
    /// This month's 1st and name, "November".
    pub month: NaiveDate,
    pub month_name: String,
    /// Last month's 1st and name, "October": the grey bars.
    pub last_month: NaiveDate,
    pub last_month_name: String,
    /// Today's day of the month and the month's length, for the chart's x axis and "of 22".
    pub day_of_month: u32,
    pub days_in_month: u32,
    /// `None` until this person's calendar loads: the view waits rather than drawing zeros.
    pub history: Option<PersonHistory>,
    /// Your race with them, on a rival's view once both calendars load; `None` on your own.
    pub race: Option<Race>,
}
/// You against a rival over the board's 30 days through today (Swift's `PersonSummary.Race`):
/// the same totals the board ranks on 30 days.
#[derive(Clone, Debug, Serialize, PartialEq)]
pub struct Race {
    /// The first day raced; each running total's index counts on from it.
    pub start: NaiveDate,
    /// Running totals from `start`, one per day (`history::running`).
    pub yours: Vec<u32>,
    pub theirs: Vec<u32>,
    pub story: history::RaceStory,
}
#[derive(Clone, Debug, Serialize, PartialEq)]
pub struct PersonHistory {
    /// Each day's count from the 1st through today (`history::series`).
    pub this_month: Vec<u32>,
    /// Each day's count for every day of last month.
    pub last_month: Vec<u32>,
    pub current_streak: u32,
    /// The longest run in the calendar, about the past year.
    pub longest_streak: u32,
    /// Days this month with a contribution: "Active days: 18 of 22" (22 = `day_of_month`).
    pub active_days: u32,
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
    #[serde(default)]
    as_of: Option<NaiveDate>,
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
    /// Today's ranks at the first refresh of the day: the movement chevrons compare against them.
    baseline: Option<(NaiveDate, BTreeMap<String, usize>)>,
    previous: BTreeMap<Window, (NaiveDate, BTreeMap<String, u32>)>,
    /// The person the person window shows (`select_person`).
    person: Option<String>,
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
        let rows = ranked_rows(&state, window, today, self.clock.now());
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
    /// The person view for someone on the board now, or `None` for anyone hidden or not on it.
    pub fn person(&self, login: &str) -> Option<PersonView> {
        let state = self.state.lock().unwrap();
        let today = self.clock.today();
        let login = login.to_ascii_lowercase();
        let row = ranked_rows(&state, Window::Today, today, self.clock.now())
            .into_iter()
            .find(|row| row.person.login == login)?;
        let month = history::first_of_month(today);
        let last_month = previous_month(today);
        // A rival's view races them against you over the board's 30 days.
        let me = state.saved.owner.as_ref().filter(|_| !row.is_you);
        let race = me
            .and_then(|me| state.saved.counts.get(me))
            .zip(state.saved.counts.get(&login))
            .map(|(mine, theirs)| {
                let days = history::range(Window::Monthly, today);
                let yours = history::running(&history::series(&mine.days, days.clone()));
                let theirs = history::running(&history::series(&theirs.days, days.clone()));
                Race {
                    start: *days.start(),
                    story: history::race_story(&yours, &theirs),
                    yours,
                    theirs,
                }
            });
        let history = state.saved.counts.get(&login).map(|snapshot| {
            let days = &snapshot.days;
            let this_month = month..=today;
            PersonHistory {
                this_month: history::series(days, this_month.clone()),
                last_month: history::series(days, history::month_range(last_month)),
                current_streak: history::current_streak(days, today),
                longest_streak: history::longest_streak(days, today),
                active_days: history::active_days(days, this_month),
            }
        });
        Some(PersonView {
            is_you: row.is_you,
            status: row.status,
            person: row.person,
            month,
            month_name: month.format("%B").to_string(),
            last_month,
            last_month_name: last_month.format("%B").to_string(),
            day_of_month: today.day(),
            days_in_month: history::days_in_month(today),
            history,
            race,
        })
    }
    /// Chooses whose view the person window shows; only someone on the board now.
    pub fn select_person(&self, login: &str) -> Result<(), String> {
        let login = login.to_ascii_lowercase();
        let mut state = self.state.lock().unwrap();
        if !state
            .saved
            .people
            .iter()
            .any(|p| p.login == login && !state.saved.hidden(&p.login))
        {
            return Err("Person is not on your board".into());
        }
        state.person = Some(login);
        Ok(())
    }
    pub fn selected_person(&self) -> Option<String> {
        self.state.lock().unwrap().person.clone()
    }
    pub fn select_window(&self, window: Window) {
        self.state.lock().unwrap().selected = window;
    }
    pub fn selected_window(&self) -> Window {
        self.state.lock().unwrap().selected
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
                as_of: Some(self.clock.today()),
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
        state.person = None;
        state.failed.clear();
        state.baseline = None;
        state.previous.clear();
        self.persist(&state)
    }
}
/// The board's order, the same rule as Swift's `Ranking.order` and the relay's `order`:
/// contributions descending, someone with no count last (below a real 0), ties in `competitors`
/// order (you are first, so you win ties), ranks from 1. Checked against
/// `fixtures/ranking-conformance.json` by `tests/conformance.rs`.
pub fn order(competitors: &[String], counts: &BTreeMap<String, u32>) -> Vec<(String, usize)> {
    let mut ordered: Vec<&String> = competitors.iter().collect();
    ordered.sort_by_key(|login| std::cmp::Reverse(counts.get(*login)));
    ordered
        .into_iter()
        .enumerate()
        .map(|(index, login)| (login.clone(), index + 1))
        .collect()
}
fn ranked_rows(state: &State, window: Window, today: NaiveDate, now: i64) -> Vec<Row> {
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
                contributions: snapshot.map(|s| history::total(&s.days, window, today)),
                streak: snapshot.map(|s| history::current_streak(&s.days, today)),
                burst: snapshot.and_then(|s| parser::burst(&s.days, history::range(window, today))),
                is_you: state.saved.owner.as_ref() == Some(&person.login),
                movement: 0,
                status: if state.failed.contains_key(&person.login) {
                    "failed"
                } else if state.refreshing {
                    "loading"
                } else if snapshot.is_some_and(|s| now - s.updated > 120 || s.as_of != Some(today))
                {
                    "cached"
                } else if snapshot.is_some() {
                    "loaded"
                } else {
                    "missing"
                }
                .into(),
            }
        })
        .collect();
    let logins: Vec<String> = rows.iter().map(|row| row.person.login.clone()).collect();
    let counts: BTreeMap<String, u32> = rows
        .iter()
        .filter_map(|row| Some((row.person.login.clone(), row.contributions?)))
        .collect();
    let ranks: BTreeMap<String, usize> = order(&logins, &counts).into_iter().collect();
    rows.sort_by_key(|row| ranks[&row.person.login]);
    for row in rows.iter_mut() {
        row.rank = ranks[&row.person.login];
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
/// The 1st of the month before `today`'s.
fn previous_month(today: NaiveDate) -> NaiveDate {
    history::first_of_month(today)
        .checked_sub_months(chrono::Months::new(1))
        .expect("a month before a calendar day")
}
fn valid_login(login: &str) -> bool {
    !login.is_empty()
        && login.len() <= 39
        && login
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || c == b'-')
}
