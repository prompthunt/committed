//! Pure calculations over one person's daily contribution counts: the Windows mirror of Swift's
//! `ContributionHistory`. Keys are GitHub's civil days and `today` is the local day from the
//! `Clock`, so nothing here reads the time or a time zone. `series`, `active_days`,
//! `month_range` and `days_in_month` serve the person view.
use crate::Window;
use chrono::{Datelike, Duration, NaiveDate};
use std::collections::BTreeMap;
use std::ops::RangeInclusive;

/// The days `window` covers as of `today`, inclusive: each Window ends today and reaches back a
/// fixed number of days.
pub fn range(window: Window, today: NaiveDate) -> RangeInclusive<NaiveDate> {
    let start = match window {
        Window::Today => today,
        Window::Week => today - Duration::days(6),
        Window::Monthly => today - Duration::days(29),
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

/// The longest run of consecutive days with a contribution anywhere in the calendar through
/// `today` (about the past year). Days after `today` never count, and a day missing from the
/// calendar breaks a run, like `current_streak`.
pub fn longest_streak(days: &BTreeMap<NaiveDate, u32>, today: NaiveDate) -> u32 {
    let mut longest = 0;
    let mut run = 0;
    let mut previous: Option<NaiveDate> = None;
    for (day, count) in days.range(..=today) {
        if *count == 0 {
            run = 0;
        } else if previous.is_some_and(|p| *day - p == Duration::days(1)) && run > 0 {
            run += 1;
        } else {
            run = 1;
        }
        longest = longest.max(run);
        previous = Some(*day);
    }
    longest
}

/// The person view's bars: each day's count in `range`, first day first, 0 for a day the
/// calendar doesn't have: the 1st through today for this month, `month_range(month)` for last
/// month.
pub fn series(days: &BTreeMap<NaiveDate, u32>, range: RangeInclusive<NaiveDate>) -> Vec<u32> {
    range
        .start()
        .iter_days()
        .take_while(|day| day <= range.end())
        .map(|day| days.get(&day).copied().unwrap_or(0))
        .collect()
}

/// Days in `range` with at least one contribution: the 18 in "Active days: 18 of 22".
pub fn active_days(days: &BTreeMap<NaiveDate, u32>, range: RangeInclusive<NaiveDate>) -> u32 {
    days.range(range).filter(|(_, count)| **count > 0).count() as u32
}

/// Every day of the month that contains `month` (any day of it names the month), 1st to last:
/// the person view's last month.
pub fn month_range(month: NaiveDate) -> RangeInclusive<NaiveDate> {
    let first = first_of_month(month);
    first..=next_month(first) - Duration::days(1)
}

/// How many days `today`'s month has (28 to 31): the person view's chart width.
pub fn days_in_month(today: NaiveDate) -> u32 {
    (next_month(today) - first_of_month(today)).num_days() as u32
}

/// The 1st of `day`'s month.
pub fn first_of_month(day: NaiveDate) -> NaiveDate {
    day.with_day(1).expect("every month has a 1st")
}

/// The 1st of the month after `day`'s.
pub fn next_month(day: NaiveDate) -> NaiveDate {
    first_of_month(day)
        .checked_add_months(chrono::Months::new(1))
        .expect("a month after a calendar day")
}
