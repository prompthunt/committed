use super::*;

pub(crate) fn finish_refresh(state: &mut State, today: NaiveDate, now: i64) -> Vec<Notification> {
    let daily = ranked_rows(state, Window::Today, today, now);
    if state.baseline.as_ref().is_none_or(|(day, _)| *day != today)
        && daily
            .iter()
            .any(|r| r.contributions.is_some() && !state.failed.contains_key(&r.person.login))
    {
        state.baseline = Some((
            today,
            daily
                .iter()
                .filter(|r| {
                    r.contributions.is_some() && !state.failed.contains_key(&r.person.login)
                })
                .map(|r| (r.person.login.clone(), r.rank))
                .collect(),
        ));
    }
    let window = state.selected;
    let current: BTreeMap<_, _> = ranked_rows(state, window, today, now)
        .iter()
        .filter(|r| !state.failed.contains_key(&r.person.login))
        .filter_map(|r| Some((r.person.login.clone(), r.contributions?)))
        .collect();
    let previous = state.previous.insert(window, (today, current.clone()));
    if !state.saved.settings.notifications {
        return vec![];
    }
    let Some((_, previous)) = previous.filter(|(day, _)| *day == today) else {
        return vec![];
    };
    let Some(owner) = &state.saved.owner else {
        return vec![];
    };
    let (Some(&before), Some(&now)) = (previous.get(owner), current.get(owner)) else {
        return vec![];
    };
    let mut notifications = vec![];
    for (login, &rival_now) in &current {
        if login == owner {
            continue;
        }
        let Some(&rival_before) = previous.get(login) else {
            continue;
        };
        if rival_before <= before && rival_now > now {
            notifications.push(Notification {
                title: format!("😤 {login} passed you"),
                body: format!("They're ahead {rival_now}–{now}. Time to catch up!"),
            });
        } else if rival_before >= before && rival_now < now {
            notifications.push(Notification {
                title: format!("🎉 You passed {login}!"),
                body: format!("You're ahead {now}–{rival_now}. Keep climbing!"),
            });
        }
    }
    // Match NotificationService on the Mac: summarize a flurry of more than three.
    if notifications.len() > 3 {
        vec![Notification {
            title: format!("{} position changes", notifications.len()),
            body: "Your standings shifted since the last check.".into(),
        }]
    } else {
        notifications
    }
}
