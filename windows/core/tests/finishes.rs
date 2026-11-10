//! Table tests for a finished month's ranks and medals (`committed_core::finishes`), mirroring the
//! Swift finishes cases in #98: the board's ranking with you first on ties, medals for ranks 1–3
//! only when that month's total is above zero, and someone with no calendar last without a medal.
use committed_core::{finishes, Finish, Medal};
use std::collections::BTreeMap;

/// login, rank, total, medal
type Place = (String, usize, Option<u32>, Option<Medal>);
/// name, competitors (you first), month totals, expected places
type Case<'a> = (&'a str, &'a [&'a str], &'a [(&'a str, u32)], Vec<Place>);

fn run(competitors: &[&str], totals: &[(&str, u32)]) -> Vec<Place> {
    let competitors: Vec<String> = competitors.iter().map(|s| s.to_string()).collect();
    let totals: BTreeMap<String, u32> = totals.iter().map(|(l, n)| (l.to_string(), *n)).collect();
    finishes(&competitors, &totals)
        .into_iter()
        .map(
            |Finish {
                 login,
                 rank,
                 total,
                 medal,
             }| (login, rank, total, medal),
        )
        .collect()
}

fn f(login: &str, rank: usize, total: Option<u32>, medal: Option<Medal>) -> Place {
    (login.into(), rank, total, medal)
}

#[test]
fn finishes_rank_like_the_board_and_medal_the_top_three_above_zero() {
    use Medal::*;
    let cases: &[Case] = &[
        (
            "top three medal, fourth doesn't",
            &["me", "a", "b", "c"],
            &[("me", 40), ("a", 90), ("b", 10), ("c", 70)],
            vec![
                f("a", 1, Some(90), Some(Gold)),
                f("c", 2, Some(70), Some(Silver)),
                f("me", 3, Some(40), Some(Bronze)),
                f("b", 4, Some(10), None),
            ],
        ),
        (
            "you win a tie",
            &["me", "a"],
            &[("a", 12), ("me", 12)],
            vec![
                f("me", 1, Some(12), Some(Gold)),
                f("a", 2, Some(12), Some(Silver)),
            ],
        ),
        (
            "no medal on a zero total",
            &["me", "a", "b"],
            &[("me", 0), ("a", 5), ("b", 0)],
            vec![
                f("a", 1, Some(5), Some(Gold)),
                f("me", 2, Some(0), None),
                f("b", 3, Some(0), None),
            ],
        ),
        (
            "a month where nobody contributed has ranks but no medals",
            &["me", "a"],
            &[("me", 0), ("a", 0)],
            vec![f("me", 1, Some(0), None), f("a", 2, Some(0), None)],
        ),
        (
            "no calendar ranks last below a real 0 and never medals",
            &["me", "ghost", "a"],
            &[("me", 0), ("a", 3)],
            vec![
                f("a", 1, Some(3), Some(Gold)),
                f("me", 2, Some(0), None),
                f("ghost", 3, None, None),
            ],
        ),
        ("nobody on the board", &[], &[], vec![]),
    ];
    for (name, competitors, totals, expected) in cases {
        assert_eq!(run(competitors, totals), *expected, "{name}");
    }
}

#[test]
fn medals_use_lowercase_names_in_json() {
    assert_eq!(serde_json::to_string(&Medal::Gold).unwrap(), r#""gold""#);
    assert_eq!(
        serde_json::to_string(&Medal::Silver).unwrap(),
        r#""silver""#
    );
    assert_eq!(
        serde_json::to_string(&Medal::Bronze).unwrap(),
        r#""bronze""#
    );
}
