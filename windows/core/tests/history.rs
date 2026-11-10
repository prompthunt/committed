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
            Window::Monthly,
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
            Window::Monthly,
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
    assert_eq!(
        history::total(&calendar, Window::Monthly, d(2026, 5, 28)),
        5
    );
    assert_eq!(
        history::total(&BTreeMap::new(), Window::Week, d(2026, 5, 28)),
        0
    );
}

/// A run of `length` days with one contribution each, ending on `last`.
fn run(last: NaiveDate, length: i64) -> Vec<(NaiveDate, u32)> {
    (0..length)
        .map(|back| (last - chrono::Duration::days(back), 1))
        .collect()
}

#[test]
fn current_streaks() {
    let today = d(2026, 5, 28);
    let yesterday = d(2026, 5, 27);
    let with = |mut cells: Vec<(NaiveDate, u32)>, extra: &[(NaiveDate, u32)]| {
        cells.extend_from_slice(extra);
        days(&cells)
    };
    let cases: Vec<(&str, BTreeMap<NaiveDate, u32>, NaiveDate, u32)> = vec![
        ("contributed today", with(run(today, 12), &[]), today, 12),
        (
            "today zero, yesterday not: still alive through today",
            with(run(yesterday, 12), &[(today, 0)]),
            today,
            12,
        ),
        (
            "today not in the calendar yet, yesterday was: alive",
            with(run(yesterday, 5), &[]),
            today,
            5,
        ),
        (
            "today and yesterday zero: broken, however long the run before",
            with(run(d(2026, 5, 26), 40), &[(yesterday, 0), (today, 0)]),
            today,
            0,
        ),
        (
            "a zero day ends the run",
            with(run(today, 3), &[(d(2026, 5, 25), 0), (d(2026, 5, 24), 9)]),
            today,
            3,
        ),
        (
            "one day is a streak of 1",
            days(&[(today, 4), (yesterday, 0)]),
            today,
            1,
        ),
        // Midnight: at 23:59 the 28th's run is alive; at 00:00 on the 29th, with nothing yet,
        // it's still alive; on the 30th with nothing on the 29th it's broken.
        ("just before midnight", with(run(today, 7), &[]), today, 7),
        (
            "just after midnight, nothing yet",
            with(run(today, 7), &[]),
            d(2026, 5, 29),
            7,
        ),
        (
            "a whole day missed",
            with(run(today, 7), &[(d(2026, 5, 29), 0)]),
            d(2026, 5, 30),
            0,
        ),
        (
            "across a leap day",
            with(run(d(2028, 3, 2), 5), &[]),
            d(2028, 3, 2),
            5, // Feb 27, 28, 29, Mar 1, 2
        ),
        (
            "across the US DST change (Mar 8 2026)",
            with(run(d(2026, 3, 10), 4), &[]),
            d(2026, 3, 10),
            4,
        ),
        (
            "a calendar shorter than the run counts the days it has",
            with(run(today, 20), &[]),
            today,
            20,
        ),
        ("exactly 365 days", with(run(today, 365), &[]), today, 365),
        (
            "a whole GitHub calendar (371 days)",
            with(run(today, 371), &[]),
            today,
            371,
        ),
        (
            "future days never count",
            with(run(d(2026, 6, 2), 10), &[]),
            today,
            5, // May 24..28; May 29..Jun 2 are after today
        ),
        ("no calendar at all", BTreeMap::new(), today, 0),
    ];
    for (name, calendar, today, expected) in cases {
        assert_eq!(
            history::current_streak(&calendar, today),
            expected,
            "{name}"
        );
    }
}

#[test]
fn windows_use_the_mac_and_iphone_raw_values_for_30_days_and_this_month() {
    // Swift and the relay call 30 days "monthly" and This month "month"; Windows matches them.
    assert_eq!(
        serde_json::to_string(&Window::Monthly).unwrap(),
        r#""monthly""#
    );
    assert_eq!(
        serde_json::to_string(&Window::ThisMonth).unwrap(),
        r#""month""#
    );
    assert_eq!(
        serde_json::from_str::<Window>(r#""month""#).unwrap(),
        Window::ThisMonth
    );
    assert_eq!(serde_json::to_string(&Window::Today).unwrap(), r#""today""#);
    assert_eq!(serde_json::to_string(&Window::Week).unwrap(), r#""week""#);
}

#[test]
fn this_month_counts_the_local_calendar_month_to_date() {
    let calendar = days(&[
        (d(2026, 1, 31), 50), // the day before February: never in February's total
        (d(2026, 2, 1), 1),
        (d(2026, 2, 14), 2),
        (d(2026, 2, 28), 4), // last day of a 28-day February
        (d(2026, 3, 1), 8),
        (d(2026, 3, 8), 16), // US DST starts
        (d(2026, 4, 1), 3),
        (d(2026, 4, 30), 5), // last day of a 30-day April
        (d(2026, 5, 1), 10),
        (d(2026, 5, 27), 20),
        (d(2026, 5, 28), 30),
        (d(2026, 5, 29), 40), // after today on May 28
        (d(2026, 5, 31), 60), // last day of a 31-day May
        (d(2026, 6, 1), 7),
        (d(2026, 12, 31), 9),
        (d(2027, 1, 1), 11),
        (d(2028, 2, 28), 2),
        (d(2028, 2, 29), 6), // leap day
        (d(2028, 3, 1), 1),
    ]);
    let cases: &[(&str, NaiveDate, u32)] = &[
        (
            "May 28: May 1 to 28, future days ignored",
            d(2026, 5, 28),
            60,
        ),
        ("last day of a 31-day month", d(2026, 5, 31), 160),
        ("the 1st resets to just today", d(2026, 6, 1), 7),
        ("the 1st with nothing yet is 0", d(2026, 7, 1), 0),
        ("last day of a 28-day February", d(2026, 2, 28), 7),
        ("Mar 1 after February starts again", d(2026, 3, 1), 8),
        ("across the DST change", d(2026, 3, 9), 24),
        ("last day of a 30-day April", d(2026, 4, 30), 8),
        ("Dec 31", d(2026, 12, 31), 9),
        ("Jan 1 does not reach back into December", d(2027, 1, 1), 11),
        ("29-day February on the leap day", d(2028, 2, 29), 8),
        ("Mar 1 after a leap day", d(2028, 3, 1), 1),
        // Midnight on the 1st in different zones: at 2026-05-31T15:30Z it's already June 1 in
        // Tokyo but still May 31 in Los Angeles. Each clock hands the core its own local day.
        ("Tokyo's month at 2026-05-31T15:30Z", d(2026, 6, 1), 7),
        (
            "Los Angeles' month at 2026-05-31T15:30Z",
            d(2026, 5, 31),
            160,
        ),
    ];
    for (name, today, expected) in cases {
        assert_eq!(
            history::total(&calendar, Window::ThisMonth, *today),
            *expected,
            "{name}"
        );
    }
}

#[test]
fn days_in_month_for_day_x_of_y() {
    let cases: &[(NaiveDate, u32)] = &[
        (d(2026, 2, 10), 28),
        (d(2028, 2, 10), 29),
        (d(2026, 4, 10), 30),
        (d(2026, 5, 10), 31),
        (d(2026, 12, 31), 31),
        (d(2027, 1, 1), 31),
    ];
    for (today, expected) in cases {
        assert_eq!(history::days_in_month(*today), *expected, "{today}");
    }
}
