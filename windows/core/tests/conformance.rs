//! Runs the shared ranking conformance fixture (`fixtures/ranking-conformance.json`) against the
//! Windows core's ranking and history, so Swift, the relay and Windows can't drift apart. Windows
//! has no Live rank, so each case's `liveRankState` is not checked here; `order` is, and for cases
//! with calendars, the Window totals they rank by and everyone's current streak.
use chrono::NaiveDate;
use committed_core::{history, order, Window};
use serde::Deserialize;
use std::collections::BTreeMap;

#[derive(Deserialize)]
struct Fixture {
    version: u32,
    cases: Vec<Case>,
}
#[derive(Deserialize)]
struct Case {
    name: String,
    input: Input,
    expected: Expected,
}
#[derive(Deserialize)]
struct Input {
    #[serde(rename = "self")]
    me: String,
    competitors: Vec<String>,
    window: String,
    /// Counts, or `days` with `timeZone` and `asOf` (never both).
    standings: Option<BTreeMap<String, Standing>>,
    days: Option<BTreeMap<String, BTreeMap<NaiveDate, u32>>>,
    #[serde(rename = "timeZone")]
    time_zone: Option<String>,
    /// The local day at `now` in `timeZone`. The core takes today from its clock and has no time
    /// zone database, so it uses this as today; Swift and the relay check their own resolution.
    #[serde(rename = "asOf")]
    as_of: Option<NaiveDate>,
}
#[derive(Deserialize)]
struct Standing {
    contributions: u32,
    window: String,
}
#[derive(Deserialize)]
struct Expected {
    order: Vec<Placed>,
    streaks: Option<BTreeMap<String, u32>>,
}
#[derive(Deserialize, Debug, PartialEq)]
struct Placed {
    login: String,
    rank: usize,
}

/// The fixture uses Swift's Window raw values. Windows' `Window` shares `"monthly"` (30 days) and
/// `"month"` (This month) but still calls Today and 7 days `"today"` and `"week"`, so the strings
/// are mapped here rather than deserialized into it.
fn window(raw: &str) -> Option<Window> {
    match raw {
        "daily" => Some(Window::Today),
        "weekly" => Some(Window::Week),
        "monthly" => Some(Window::Monthly),
        _ => None,
    }
}

/// The counts a case ranks by: given, or worked out from each person's calendar with
/// `history::total`, as the board does. A standing for another Window is no data for this one.
fn counts(case: &Case) -> BTreeMap<String, u32> {
    let input = &case.input;
    let selected =
        window(&input.window).unwrap_or_else(|| panic!("{}: window {}", case.name, input.window));
    match (&input.standings, &input.days) {
        (Some(standings), None) => standings
            .iter()
            .filter(|(_, standing)| {
                assert!(window(&standing.window).is_some(), "{}", case.name);
                standing.window == input.window
            })
            .map(|(login, standing)| (login.clone(), standing.contributions))
            .collect(),
        (None, Some(days)) => {
            assert!(
                input.time_zone.is_some(),
                "{}: days need a time zone",
                case.name
            );
            let today = input
                .as_of
                .unwrap_or_else(|| panic!("{}: days need asOf", case.name));
            days.iter()
                .map(|(login, calendar)| (login.clone(), history::total(calendar, selected, today)))
                .collect()
        }
        _ => panic!("{}: give standings or days, not both", case.name),
    }
}

fn fixture() -> Fixture {
    serde_json::from_str(include_str!("../../../fixtures/ranking-conformance.json")).unwrap()
}

#[test]
fn ranking_matches_the_shared_fixture() {
    let fixture = fixture();
    assert_eq!(fixture.version, 1);
    assert!(!fixture.cases.is_empty());
    for case in &fixture.cases {
        let input = &case.input;
        assert_eq!(
            input.competitors.first(),
            Some(&input.me),
            "{}: you come first",
            case.name
        );
        let placed: Vec<Placed> = order(&input.competitors, &counts(case))
            .into_iter()
            .map(|(login, rank)| Placed { login, rank })
            .collect();
        assert_eq!(placed, case.expected.order, "{}", case.name);
    }
}

#[test]
fn streaks_match_the_shared_fixture() {
    let fixture = fixture();
    let mut checked = 0;
    for case in &fixture.cases {
        let Some(days) = &case.input.days else {
            assert!(
                case.expected.streaks.is_none(),
                "{}: streaks need days",
                case.name
            );
            continue;
        };
        let today = case.input.as_of.unwrap();
        let streaks: BTreeMap<String, u32> = days
            .iter()
            .map(|(login, calendar)| (login.clone(), history::current_streak(calendar, today)))
            .collect();
        assert_eq!(
            Some(&streaks),
            case.expected.streaks.as_ref(),
            "{}",
            case.name
        );
        checked += 1;
    }
    assert!(checked > 0, "the fixture has streak cases");
}
