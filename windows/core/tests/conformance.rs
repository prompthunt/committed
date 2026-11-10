//! Runs the shared ranking conformance fixture (`fixtures/ranking-conformance.json`) against the
//! Windows core's ranking, so Swift, the relay and Windows can't drift apart. Windows has no Live
//! rank, so each case's `liveRankState` is not checked here; `order` is.
use committed_core::order;
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
    standings: BTreeMap<String, Standing>,
}
#[derive(Deserialize)]
struct Standing {
    contributions: u32,
    window: String,
}
#[derive(Deserialize)]
struct Expected {
    order: Vec<Placed>,
}
#[derive(Deserialize, Debug, PartialEq)]
struct Placed {
    login: String,
    rank: usize,
}

/// The fixture uses Swift's Window raw values. Windows' own `Window` serializes differently (its
/// 30-day Window is `"month"`), so the strings are checked here rather than deserialized into it.
fn known_window(raw: &str) -> bool {
    matches!(raw, "daily" | "weekly" | "monthly")
}

#[test]
fn ranking_matches_the_shared_fixture() {
    let fixture: Fixture =
        serde_json::from_str(include_str!("../../../fixtures/ranking-conformance.json")).unwrap();
    assert_eq!(fixture.version, 1);
    assert!(!fixture.cases.is_empty());
    for case in fixture.cases {
        let input = case.input;
        assert!(
            known_window(&input.window),
            "{}: window {}",
            case.name,
            input.window
        );
        assert_eq!(
            input.competitors.first(),
            Some(&input.me),
            "{}: you come first",
            case.name
        );
        // A standing for another Window is no data for this one, like a missing standing.
        let counts: BTreeMap<String, u32> = input
            .standings
            .into_iter()
            .filter(|(_, standing)| {
                assert!(known_window(&standing.window), "{}", case.name);
                standing.window == input.window
            })
            .map(|(login, standing)| (login, standing.contributions))
            .collect();
        let placed: Vec<Placed> = order(&input.competitors, &counts)
            .into_iter()
            .map(|(login, rank)| Placed { login, rank })
            .collect();
        assert_eq!(placed, case.expected.order, "{}", case.name);
    }
}
