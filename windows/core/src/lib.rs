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

/// A board's time range. `Monthly` (30 days) and `ThisMonth` serialize as Swift's and the relay's
/// raw values, `"monthly"` and `"month"`, so every platform means the same thing by each string.
#[derive(Clone, Copy, Debug, Default, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "camelCase")]
pub enum Window {
    #[default]
    Today,
    Week,
    /// The last 30 days, including today.
    #[serde(rename = "monthly")]
    Monthly,
    /// The local calendar month to date: from the 1st through today, starting again on the 1st.
    #[serde(rename = "month")]
    ThisMonth,
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
    /// Set only on Final standings rows (`FinalStandings`); the live board never shows medals.
    pub medal: Option<Medal>,
}
/// A finished month's ranks among the people on the board now, with medals: recomputed from the
/// saved calendars, never frozen, so hiding or showing someone changes them like the board.
/// Rows carry the month's total in `contributions`, no streak and no movement.
#[derive(Clone, Debug, Serialize)]
pub struct FinalStandings {
    /// The month's 1st.
    pub month: NaiveDate,
    /// "October", for "October final".
    pub month_name: String,
    pub rows: Vec<Row>,
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
    /// Today's day of the local month and how many days the month has: This month's
    /// "Day 10 of 30".
    pub day_of_month: u32,
    pub days_in_month: u32,
    /// Last month's Final standings, all day on the 1st (when last month is offered).
    pub final_standings: Option<FinalStandings>,
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
    /// Per account, the last finished month whose result was announced (its 1st), so the
    /// month-final notification goes out once per month on this PC, across relaunches.
    #[serde(default)]
    announced: BTreeMap<String, NaiveDate>,
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
    /// Ranks at the first refresh of the day, for the Windows that show movement (Today and
    /// This month), so each one's chevrons compare its own ranks.
    baselines: BTreeMap<Window, (NaiveDate, BTreeMap<String, usize>)>,
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
            day_of_month: today.day(),
            days_in_month: history::days_in_month(today),
            final_standings: if today.day() == 1 {
                final_standings(&state, previous_month(today), today)
            } else {
                None
            },
        }
    }
    /// Finished months that can show Final standings, oldest first: from the calendar's first
    /// full month (`history::first_full_month`) through last month.
    pub fn finished_months(&self) -> Vec<NaiveDate> {
        let state = self.state.lock().unwrap();
        let today = self.clock.today();
        let mut months = vec![];
        let Some(mut month) = first_offered_month(&state) else {
            return months;
        };
        let current = today.with_day(1).expect("every month has a 1st");
        while month < current {
            months.push(month);
            month = month
                .checked_add_months(chrono::Months::new(1))
                .expect("a month after a calendar day");
        }
        months
    }
    /// The Final standings for the month containing `month`, or `None` when that month isn't
    /// finished or starts before the calendar's first full month.
    pub fn final_standings(&self, month: NaiveDate) -> Option<FinalStandings> {
        let state = self.state.lock().unwrap();
        final_standings(&state, month, self.clock.today())
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
        state.baselines.clear();
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
        state.baselines.clear();
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
/// Gold, silver and bronze: ranks 1–3 of a finished month whose total was above zero.
#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum Medal {
    Gold,
    Silver,
    Bronze,
}
/// One person's place in a finished month.
#[derive(Clone, Debug, PartialEq)]
pub struct Finish {
    pub login: String,
    pub rank: usize,
    /// That month's contributions; `None` when this person's calendar hasn't loaded.
    pub total: Option<u32>,
    pub medal: Option<Medal>,
}
/// A finished month's ranks and medals among `competitors` (you first, so you win ties): the
/// board's `order` over each person's month total, a medal for ranks 1–3 when that total is
/// above zero. Someone without a total ranks last and never gets a medal.
pub fn finishes(competitors: &[String], totals: &BTreeMap<String, u32>) -> Vec<Finish> {
    order(competitors, totals)
        .into_iter()
        .map(|(login, rank)| {
            let total = totals.get(&login).copied();
            let medal = match (rank, total) {
                (_, None | Some(0)) => None,
                (1, _) => Some(Medal::Gold),
                (2, _) => Some(Medal::Silver),
                (3, _) => Some(Medal::Bronze),
                _ => None,
            };
            Finish {
                login,
                rank,
                total,
                medal,
            }
        })
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
                is_you: state.saved.owner.as_ref() == Some(&person.login),
                movement: 0,
                medal: None,
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
        if row.contributions.is_some() && !state.failed.contains_key(&row.person.login) {
            row.movement = state
                .baselines
                .get(&window)
                .filter(|(day, _)| *day == today)
                .and_then(|(_, ranks)| ranks.get(&row.person.login))
                .map(|rank| *rank as i32 - row.rank as i32)
                .unwrap_or(0);
        }
    }
    rows
}
/// The 1st of the month before `today`'s.
pub(crate) fn previous_month(today: NaiveDate) -> NaiveDate {
    today
        .with_day(1)
        .and_then(|first| first.checked_sub_months(chrono::Months::new(1)))
        .expect("a month before a calendar day")
}
/// The first month offered as finished: the first full month of your calendar (the first person
/// on the board is you). Everyone's calendar covers the same year, so yours decides.
fn first_offered_month(state: &State) -> Option<NaiveDate> {
    let first = state.saved.people.first()?;
    history::first_full_month(&state.saved.counts.get(&first.login)?.days)
}
pub(crate) fn final_standings(
    state: &State,
    month: NaiveDate,
    today: NaiveDate,
) -> Option<FinalStandings> {
    let month = month.with_day(1)?;
    let current = today.with_day(1)?;
    if month >= current || month < first_offered_month(state)? {
        return None;
    }
    let people: Vec<&Person> = state
        .saved
        .people
        .iter()
        .filter(|p| !state.saved.hidden(&p.login))
        .collect();
    let logins: Vec<String> = people.iter().map(|p| p.login.clone()).collect();
    let totals: BTreeMap<String, u32> = people
        .iter()
        .filter_map(|p| {
            let snapshot = state.saved.counts.get(&p.login)?;
            Some((p.login.clone(), history::month_total(&snapshot.days, month)))
        })
        .collect();
    let rows = finishes(&logins, &totals)
        .into_iter()
        .map(|finish| {
            let person = people
                .iter()
                .find(|p| p.login == finish.login)
                .expect("a finish for each person");
            Row {
                person: (*person).clone(),
                rank: finish.rank,
                contributions: finish.total,
                streak: None,
                is_you: state.saved.owner.as_ref() == Some(&finish.login),
                movement: 0,
                status: if finish.total.is_some() {
                    "loaded"
                } else {
                    "missing"
                }
                .into(),
                medal: finish.medal,
            }
        })
        .collect();
    Some(FinalStandings {
        month,
        month_name: month.format("%B").to_string(),
        rows,
    })
}
fn valid_login(login: &str) -> bool {
    !login.is_empty()
        && login.len() <= 39
        && login
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || c == b'-')
}
