use committed_core::*;
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

#[derive(Default)]
struct FakeHttp(Mutex<BTreeMap<String, Result<String, String>>>);
#[async_trait::async_trait]
impl Http for FakeHttp {
    async fn request(&self, request: Request) -> Result<String, String> {
        assert!(request.token.is_none() || request.url.starts_with("https://api.github.com/"));
        self.0
            .lock()
            .unwrap()
            .get(&request.url)
            .cloned()
            .unwrap_or_else(|| Err(format!("Unexpected request: {}", request.url)))
    }
}
struct TestClock(Mutex<i64>);
impl Clock for TestClock {
    fn now(&self) -> i64 {
        *self.0.lock().unwrap()
    }
    fn today(&self) -> chrono::NaiveDate {
        chrono::DateTime::from_timestamp(self.now(), 0)
            .unwrap()
            .date_naive()
    }
}
#[derive(Default)]
struct Memory(Mutex<Option<String>>);
impl Storage for Memory {
    fn load(&self) -> Result<Option<String>, String> {
        Ok(self.0.lock().unwrap().clone())
    }
    fn save(&self, value: &str) -> Result<(), String> {
        *self.0.lock().unwrap() = Some(value.into());
        Ok(())
    }
}
#[derive(Default)]
struct Credentials(Mutex<Option<String>>);
impl CredentialStore for Credentials {
    fn get(&self) -> Result<Option<String>, String> {
        Ok(self.0.lock().unwrap().clone())
    }
    fn set(&self, token: Option<&str>) -> Result<(), String> {
        *self.0.lock().unwrap() = token.map(str::to_owned);
        Ok(())
    }
}
#[derive(Default)]
struct Notifications(Mutex<Vec<Notification>>);
impl Notifier for Notifications {
    fn post(&self, notification: Notification) {
        self.0.lock().unwrap().push(notification);
    }
}
struct Fixture {
    core: BoardCore,
    http: Arc<FakeHttp>,
    clock: Arc<TestClock>,
    storage: Arc<Memory>,
    credentials: Arc<Credentials>,
    notifications: Arc<Notifications>,
}
impl Fixture {
    fn new() -> Self {
        let http = Arc::new(FakeHttp::default());
        let clock = Arc::new(TestClock(Mutex::new(1779969600))); // 2026-05-28 noon UTC
        let storage = Arc::new(Memory::default());
        let credentials = Arc::new(Credentials::default());
        let notifications = Arc::new(Notifications::default());
        let core = BoardCore::new(
            http.clone(),
            clock.clone(),
            storage.clone(),
            credentials.clone(),
            notifications.clone(),
        )
        .unwrap();
        Self {
            core,
            http,
            clock,
            storage,
            credentials,
            notifications,
        }
    }
    fn response(&self, url: &str, body: &str) {
        self.http
            .0
            .lock()
            .unwrap()
            .insert(url.into(), Ok(body.into()));
    }
    fn contributions(&self, login: &str, html: &str) {
        self.response(
            &format!("https://github.com/users/{login}/contributions"),
            html,
        );
    }
    async fn connect(&self) {
        self.response("https://github.com/login/device/code", r#"{"device_code":"private-code","user_code":"ABCD","verification_uri":"https://github.com/login/device","expires_in":900,"interval":1}"#);
        self.core.start_connect().await.unwrap();
        *self.clock.0.lock().unwrap() += 1;
        self.response(
            "https://github.com/login/oauth/access_token",
            r#"{"access_token":"token"}"#,
        );
        self.response(
            "https://api.github.com/user",
            r#"{"login":"octocat","name":"Mona"}"#,
        );
        self.core.poll_connect().await.unwrap();
        self.response(
            "https://api.github.com/user/following?per_page=100&page=1",
            "[]",
        );
        self.response("https://api.github.com/user/orgs?per_page=100&page=1", "[]");
    }
    fn count(&self, login: &str, count: u32) {
        self.contributions(
            login,
            &format!(r#"<td data-date="2026-05-28" data-count="{count}"></td>"#),
        );
    }
}

#[tokio::test]
async fn public_board_sums_modern_tooltips_for_all_windows() {
    let f = Fixture::new();
    f.contributions("octocat", include_str!("fixtures/modern.html"));
    f.core.preview("octocat").await.unwrap();
    assert_eq!(f.core.board(Window::Today).rows[0].contributions, Some(12));
    assert_eq!(f.core.board(Window::Week).rows[0].contributions, Some(15));
    assert_eq!(f.core.board(Window::Month).rows[0].contributions, Some(115));
}

#[tokio::test]
async fn legacy_counts_and_aria_labels_match_the_mac_parser() {
    let f = Fixture::new();
    f.contributions("octocat", r#"<td data-date="2026-05-28" data-count="9"></td><td data-date="2026-05-27"><span aria-label="7 contributions on Wednesday"></span></td><td data-date="2026-05-26" aria-label="No contributions on Tuesday"></td>"#);
    f.core.preview("octocat").await.unwrap();
    assert_eq!(f.core.board(Window::Week).rows[0].contributions, Some(16));
}

#[tokio::test]
async fn comma_counts_and_parse_failure_do_not_become_zero_activity() {
    let f = Fixture::new();
    f.contributions("octocat", r#"<td data-date="2026-05-28" id="x"></td><tool-tip for="x">1,234 contributions on Thursday</tool-tip>"#);
    f.core.preview("octocat").await.unwrap();
    assert_eq!(
        f.core.board(Window::Today).rows[0].contributions,
        Some(1234)
    );
    f.contributions("octocat", "<html>Not a contribution graph</html>");
    assert!(f.core.preview("octocat").await.is_err());
    assert_eq!(
        f.core.board(Window::Today).rows[0].contributions,
        Some(1234)
    );
}

#[tokio::test]
async fn device_flow_honors_poll_interval_and_connects_without_exposing_token() {
    let f = Fixture::new();
    f.response("https://github.com/login/device/code", r#"{"device_code":"private-code","user_code":"ABCD-EFGH","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#);
    let device = f.core.start_connect().await.unwrap();
    assert_eq!(device.user_code, "ABCD-EFGH");
    assert_eq!(f.core.poll_connect().await.unwrap(), ConnectStatus::Pending);
    *f.clock.0.lock().unwrap() += 5;
    f.response(
        "https://github.com/login/oauth/access_token",
        r#"{"access_token":"secret-token"}"#,
    );
    f.response(
        "https://api.github.com/user",
        r#"{"login":"octocat","name":"Mona","avatar_url":null}"#,
    );
    assert_eq!(
        f.core.poll_connect().await.unwrap(),
        ConnectStatus::Connected
    );
    assert_eq!(f.credentials.get().unwrap(), Some("secret-token".into()));
    assert!(f.core.board(Window::Today).rows[0].is_you);
    assert!(!f.storage.load().unwrap().unwrap().contains("secret-token"));
    f.core.disconnect().unwrap();
    assert_eq!(f.credentials.get().unwrap(), None);
    assert!(f.core.board(Window::Today).rows.is_empty());
}

#[tokio::test]
async fn people_sync_deduplicates_sources_ranks_stably_and_preserves_roster_on_failure() {
    let f = Fixture::new();
    f.connect().await;
    f.response(
        "https://api.github.com/user/following?per_page=100&page=1",
        r#"[{"login":"Zoe"},{"login":"alice"}]"#,
    );
    f.response(
        "https://api.github.com/user/orgs?per_page=100&page=1",
        r#"[{"login":"team"}]"#,
    );
    f.response(
        "https://api.github.com/orgs/team/members?per_page=100&page=1",
        r#"[{"login":"zoe"},{"login":"bob"}]"#,
    );
    f.count("octocat", 9);
    f.count("zoe", 12);
    f.count("alice", 12);
    f.core.refresh(RefreshReason::Manual).await.unwrap();
    let board = f.core.board(Window::Today);
    assert_eq!(
        board
            .rows
            .iter()
            .map(|r| r.person.login.as_str())
            .collect::<Vec<_>>(),
        ["zoe", "alice", "octocat", "bob"]
    );
    assert_eq!(board.rows[3].contributions, None);
    assert_eq!(
        f.core.people("", PeopleFilter::Organizations)[1]
            .person
            .login,
        "zoe"
    );
    f.response(
        "https://api.github.com/user/following?per_page=100&page=1",
        "[]",
    );
    f.http
        .0
        .lock()
        .unwrap()
        .remove("https://api.github.com/orgs/team/members?per_page=100&page=1");
    f.core.refresh(RefreshReason::Manual).await.unwrap();
    assert_eq!(f.core.board(Window::Today).rows.len(), 4);
    assert!(f.core.board(Window::Today).people_error.is_some());
}

#[tokio::test]
async fn cached_board_survives_restart_and_only_stale_opens_refresh() {
    let f = Fixture::new();
    f.connect().await;
    f.count("octocat", 7);
    f.core.refresh(RefreshReason::Manual).await.unwrap();
    f.count("octocat", 12);
    f.core.refresh(RefreshReason::Opened).await.unwrap();
    assert_eq!(f.core.board(Window::Today).rows[0].contributions, Some(7));
    *f.clock.0.lock().unwrap() += 121;
    f.core.refresh(RefreshReason::WindowChanged).await.unwrap();
    assert_eq!(f.core.board(Window::Today).rows[0].contributions, Some(12));
    let restored = BoardCore::new(
        f.http.clone(),
        f.clock.clone(),
        f.storage.clone(),
        f.credentials.clone(),
        f.notifications.clone(),
    )
    .unwrap();
    assert_eq!(restored.board(Window::Week).rows[0].contributions, Some(12));
}

#[tokio::test]
async fn hiding_people_is_local_per_account_and_survives_disconnect() {
    let f = Fixture::new();
    f.connect().await;
    f.response(
        "https://api.github.com/user/following?per_page=100&page=1",
        r#"[{"login":"alice"}]"#,
    );
    f.count("octocat", 7);
    f.count("alice", 12);
    f.core.refresh(RefreshReason::Manual).await.unwrap();
    f.core.set_hidden("alice", true).unwrap();
    assert_eq!(f.core.board(Window::Today).rows.len(), 1);
    assert!(f.core.people("ali", PeopleFilter::Following)[0].hidden);
    assert!(f.core.set_hidden("octocat", true).is_err());
    f.http
        .0
        .lock()
        .unwrap()
        .remove("https://github.com/users/alice/contributions");
    f.core.refresh(RefreshReason::Manual).await.unwrap();
    assert!(f.core.board(Window::Today).error.is_none());
    f.core.disconnect().unwrap();
    f.connect().await;
    f.response(
        "https://api.github.com/user/following?per_page=100&page=1",
        r#"[{"login":"alice"}]"#,
    );
    f.core.refresh(RefreshReason::Manual).await.unwrap();
    assert_eq!(f.core.board(Window::Today).rows.len(), 1);
    f.core.set_hidden("alice", false).unwrap();
    assert_eq!(f.core.board(Window::Today).rows.len(), 2);
}

#[tokio::test]
async fn rank_changes_use_daily_baseline_and_mac_notification_copy() {
    let f = Fixture::new();
    f.connect().await;
    f.response(
        "https://api.github.com/user/following?per_page=100&page=1",
        r#"[{"login":"alice"}]"#,
    );
    f.count("octocat", 23);
    f.count("alice", 24);
    f.core.set_setting("notifications", true).unwrap();
    f.core.refresh(RefreshReason::Manual).await.unwrap();
    assert!(f.notifications.0.lock().unwrap().is_empty());
    f.count("octocat", 25);
    f.core.refresh(RefreshReason::Manual).await.unwrap();
    assert_eq!(f.core.board(Window::Today).rows[0].movement, 1);
    assert_eq!(
        f.notifications.0.lock().unwrap().as_slice(),
        [Notification {
            title: "🎉 You passed alice!".into(),
            body: "You're ahead 25–24. Keep climbing!".into()
        }]
    );
    f.core.set_hidden("alice", true).unwrap();
    assert_eq!(f.core.board(Window::Today).rows[0].movement, 0);
    f.core.set_hidden("alice", false).unwrap();
    f.count("alice", 30);
    f.core.refresh(RefreshReason::Manual).await.unwrap();
    assert_eq!(f.notifications.0.lock().unwrap().len(), 1);
}
