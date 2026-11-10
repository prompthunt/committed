//! Table tests for the Windows mirror of Swift's `ContributionHistory`
//! (`CommitStandingsTests/ContributionHistoryTests.swift` has the same cases).
//!
//! GitHub's calendar cells are civil days (`data-date="YYYY-MM-DD"`), and the Windows core
//! receives an already-local `today` from its `Clock`. So the Swift cases that pin a time zone
//! (midnight in Tokyo vs Los Angeles, a DST day) reduce here to choosing `today`: the zone only
//! decides which civil day "now" is, and the sums never see an instant.
use chrono::NaiveDate;
use committed_core::{history, Window};
use std::collections::BTreeMap;

fn d(y: i32, m: u32, day: u32) -> NaiveDate {
    NaiveDate::from_ymd_opt(y, m, day).unwrap()
}

fn days(cells: &[(NaiveDate, u32)]) -> BTreeMap<NaiveDate, u32> {
    cells.iter().copied().collect()
}

#[test]
fn window_totals() {
    // A calendar spanning a year end, a leap February and a DST weekend, read on several days.
    let calendar = days(&[
        (d(2025, 12, 31), 4),
        (d(2026, 1, 1), 1),
        (d(2026, 1, 31), 7),
        (d(2026, 2, 1), 2),
        (d(2026, 2, 28), 3),
        (d(2026, 3, 1), 5),
        (d(2026, 3, 7), 10),
        (d(2026, 3, 8), 20), // US DST starts
        (d(2026, 3, 9), 40),
        (d(2026, 5, 21), 100), // outside 7 days of 05-28
        (d(2026, 5, 22), 1),
        (d(2026, 5, 23), 2),
        (d(2026, 5, 24), 3),
        (d(2026, 5, 25), 4),
        (d(2026, 5, 26), 5),
        (d(2026, 5, 27), 6),
        (d(2026, 5, 28), 7),
        (d(2026, 5, 29), 100), // after today: never counted
        (d(2028, 2, 29), 9),   // leap day
        (d(2028, 3, 1), 1),
    ]);
    let cases: &[(&str, Window, NaiveDate, u32)] = &[
        ("today only", Window::Today, d(2026, 5, 28), 7),
        (
            "today with nothing yet is 0",
            Window::Today,
            d(2026, 5, 30),
            0,
        ),
        (
            "7 days inclusive, future ignored",
            Window::Week,
            d(2026, 5, 28),
            28,
        ),
        (
            "30 days spans the month end",
            Window::Month,
            d(2026, 5, 28),
            128,
        ),
        ("new year's day: today", Window::Today, d(2026, 1, 1), 1),
        (
            "new year's day: 7 days reaches back into December",
            Window::Week,
            d(2026, 1, 1),
            5,
        ),
        ("Jan 31 to Feb 1: 7 days", Window::Week, d(2026, 2, 1), 9),
        (
            "Mar 1 after a 28-day February: 7 days",
            Window::Week,
            d(2026, 3, 1),
            8,
        ),
        (
            "Mar 1 after a 28-day February: 30 days reaches Jan 31",
            Window::Month,
            d(2026, 3, 1),
            17,
        ),
        ("DST day itself", Window::Today, d(2026, 3, 8), 20),
        (
            "7 days across the DST change",
            Window::Week,
            d(2026, 3, 9),
            70,
        ),
        ("leap day", Window::Today, d(2028, 2, 29), 9),
        ("7 days across a leap day", Window::Week, d(2028, 3, 1), 10),
        // Midnight in different zones: at 2026-05-28T15:30Z it's already the 29th in Tokyo
        // but still the 28th in Los Angeles. Each clock hands the core its own local day.
        (
            "Tokyo's today at 15:30Z",
            Window::Today,
            d(2026, 5, 29),
            100,
        ),
        (
            "Los Angeles' today at 15:30Z",
            Window::Today,
            d(2026, 5, 28),
            7,
        ),
    ];
    for (name, window, today, expected) in cases {
        assert_eq!(
            history::total(&calendar, *window, *today),
            *expected,
            "{name}"
        );
    }
}

#[test]
fn a_calendar_shorter_than_the_window_sums_what_it_has() {
    let calendar = days(&[(d(2026, 5, 27), 2), (d(2026, 5, 28), 3)]);
    assert_eq!(history::total(&calendar, Window::Month, d(2026, 5, 28)), 5);
    assert_eq!(
        history::total(&BTreeMap::new(), Window::Week, d(2026, 5, 28)),
        0
    );
}
