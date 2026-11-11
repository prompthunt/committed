//! Pure calculations over one person's daily contribution counts: the Windows mirror of Swift's
//! `ContributionHistory`. Keys are GitHub's civil days and `today` is the local day from the
//! `Clock`, so nothing here reads the time or a time zone. Finished months (`month_range`,
//! `month_total`, `first_full_month`) feed Final standings; the Swift functions share these names
//! in camelCase.
use crate::Window;
use chrono::{Datelike, Duration, NaiveDate};
use std::collections::BTreeMap;
use std::ops::RangeInclusive;

/// The days `window` covers as of `today`, inclusive. Today, 7 days and 30 days end today and
/// reach back a fixed number of days; This month starts on the 1st of today's month.
pub fn range(window: Window, today: NaiveDate) -> RangeInclusive<NaiveDate> {
    let start = match window {
        Window::Today => today,
        Window::Week => today - Duration::days(6),
        Window::Monthly => today - Duration::days(29),
        Window::ThisMonth => today.with_day(1).expect("every month has a 1st"),
    };
    start..=today
}

/// Contributions in `window` as of `today` (see `range`). Days after `today` are never counted,
/// and a day missing from the calendar adds 0.
pub fn total(days: &BTreeMap<NaiveDate, u32>, window: Window, today: NaiveDate) -> u32 {
    days.range(range(window, today))
        .map(|(_, count)| count)
        .sum()
}

/// Consecutive days with at least one contribution, ending today, or ending yesterday when today
/// has none yet (a streak stays alive until today is over). A day missing from the calendar
/// counts as none, so a run that reaches the calendar's first day stops there: the result never
/// exceeds what the calendar shows. This is the raw count; the board shows it only from 2, and
/// above 365 as "365+".
pub fn current_streak(days: &BTreeMap<NaiveDate, u32>, today: NaiveDate) -> u32 {
    let contributed = |day: NaiveDate| days.get(&day).is_some_and(|count| *count > 0);
    let mut day = if contributed(today) {
        today
    } else {
        today - Duration::days(1)
    };
    let mut streak = 0;
    while contributed(day) {
        streak += 1;
        day -= Duration::days(1);
    }
    streak
}

/// Every day of the month that contains `month` (any day of it names the month), 1st to last.
/// Final standings use it for a finished month; This month is `range(Window::ThisMonth, today)`.
pub fn month_range(month: NaiveDate) -> RangeInclusive<NaiveDate> {
    let first = month.with_day(1).expect("every month has a 1st");
    let last = first + Duration::days(i64::from(days_in_month(first)) - 1);
    first..=last
}

/// Contributions in the whole month that contains `month`; a day missing from the calendar adds 0.
pub fn month_total(days: &BTreeMap<NaiveDate, u32>, month: NaiveDate) -> u32 {
    days.range(month_range(month)).map(|(_, count)| count).sum()
}

/// The 1st of the first month this calendar covers in full: the calendar's first month when it
/// starts on a 1st, otherwise the month after. Earlier months aren't offered as finished months,
/// because part of them is missing. `None` for an empty calendar. GitHub renders every day of the
/// calendar, zeros included, so the first key is the first day it covers.
pub fn first_full_month(days: &BTreeMap<NaiveDate, u32>) -> Option<NaiveDate> {
    let first = *days.keys().next()?;
    let start = first.with_day(1).expect("every month has a 1st");
    Some(if first == start {
        start
    } else {
        start
            .checked_add_months(chrono::Months::new(1))
            .expect("a month after a calendar day")
    })
}

/// How many days `today`'s month has (28 to 31): the "30" in "Day 10 of 30".
pub fn days_in_month(today: NaiveDate) -> u32 {
    let first = today.with_day(1).expect("every month has a 1st");
    let next = first
        .checked_add_months(chrono::Months::new(1))
        .expect("a month after a calendar day");
    (next - first).num_days() as u32
}
