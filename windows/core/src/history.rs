//! Pure calculations over one person's daily contribution counts: the Windows mirror of Swift's
//! `ContributionHistory`. Keys are GitHub's civil days and `today` is the local day from the
//! `Clock`, so nothing here reads the time or a time zone. Finished months (`month_range`,
//! `month_total`, `first_full_month`) feed Final standings; the Swift functions share these names
//! in camelCase.
use crate::Window;
use chrono::{Datelike, Duration, NaiveDate};
use serde::Serialize;
use std::collections::BTreeMap;
use std::ops::RangeInclusive;

/// The days `window` covers as of `today`, inclusive. Today, 7 days and 30 days end today and
/// reach back a fixed number of days; This month starts on the 1st of today's month.
pub fn range(window: Window, today: NaiveDate) -> RangeInclusive<NaiveDate> {
    let start = match window {
        Window::Today => today,
        Window::Week => today - Duration::days(6),
        Window::Monthly => today - Duration::days(29),
        Window::ThisMonth => first_of_month(today),
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
/// calendar doesn't have. Pass `range(Window::ThisMonth, today)` for this month to date and
/// `month_range(month)` for a whole finished month.
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

/// Every day of the month that contains `month` (any day of it names the month), 1st to last.
/// Final standings use it for a finished month; This month is `range(Window::ThisMonth, today)`.
pub fn month_range(month: NaiveDate) -> RangeInclusive<NaiveDate> {
    let first = first_of_month(month);
    first..=next_month(first) - Duration::days(1)
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
    let start = first_of_month(first);
    Some(if first == start {
        start
    } else {
        next_month(first)
    })
}

/// How many days `today`'s month has (28 to 31): the "30" in "Day 10 of 30".
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

/// Running totals: each day's count plus every day before it in the series.
pub fn running(series: &[u32]) -> Vec<u32> {
    let mut total = 0;
    series
        .iter()
        .map(|n| {
            total += n;
            total
        })
        .collect()
}

/// Whose side of a race: yours, or the rival's.
#[derive(Clone, Copy, Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Side {
    You,
    Them,
}

/// How a race went, told by its lead: the Windows mirror of Swift's `PersonSummary.Story`. Ties
/// put you ahead on the board, so a level day keeps whoever led before it and only a strict lead
/// counts as passing.
#[derive(Clone, Copy, Debug, Serialize, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum RaceStory {
    /// Never apart.
    Level,
    /// One of you has led since the 1st.
    Led { by: Side },
    /// Level at first, then `by` pulled ahead on `day` and has led since.
    PulledAhead { by: Side, day: u32 },
    /// The lead changed hands `changes` times; `by` took it last, on `day`.
    Passed { by: Side, day: u32, changes: u32 },
    /// Level now: `by` drew level on `day`, after the other had led.
    Caught { by: Side, day: u32 },
}

/// The story of two running totals, day 1 first (`running`).
pub fn race_story(yours: &[u32], theirs: &[u32]) -> RaceStory {
    let days = yours.len().min(theirs.len());
    let leader = |i: usize| {
        if theirs[i] > yours[i] {
            Some(Side::Them)
        } else if yours[i] > theirs[i] {
            Some(Side::You)
        } else {
            None
        }
    };
    let mut leading = None;
    let (mut first_lead, mut changes, mut last_change) = (0, 0, 0);
    for i in 0..days {
        let Some(side) = leader(i) else { continue };
        match leading {
            None => {
                leading = Some(side);
                first_lead = i as u32 + 1;
            }
            Some(previous) if previous != side => {
                leading = Some(side);
                changes += 1;
                last_change = i as u32 + 1;
            }
            _ => {}
        }
    }
    let Some(leading) = leading else {
        return RaceStory::Level;
    };
    if days > 0 && leader(days - 1).is_none() {
        let mut start = days;
        while start > 1 && leader(start - 2).is_none() {
            start -= 1;
        }
        let by = if leading == Side::You {
            Side::Them
        } else {
            Side::You
        };
        return RaceStory::Caught {
            by,
            day: start as u32,
        };
    }
    if changes > 0 {
        RaceStory::Passed {
            by: leading,
            day: last_change,
            changes,
        }
    } else if first_lead == 1 {
        RaceStory::Led { by: leading }
    } else {
        RaceStory::PulledAhead {
            by: leading,
            day: first_lead,
        }
    }
}
