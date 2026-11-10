//! Pure calculations over one person's daily contribution counts: the Windows mirror of Swift's
//! `ContributionHistory`. Keys are GitHub's civil days and `today` is the local day from the
//! `Clock`, so nothing here reads the time or a time zone. Later tickets add streaks, active days
//! and month series beside `total`, with the same names as the Swift functions.
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

/// How many days `today`'s month has (28 to 31): the "30" in "Day 10 of 30".
pub fn days_in_month(today: NaiveDate) -> u32 {
    let first = today.with_day(1).expect("every month has a 1st");
    let next = first
        .checked_add_months(chrono::Months::new(1))
        .expect("a month after a calendar day");
    (next - first).num_days() as u32
}
