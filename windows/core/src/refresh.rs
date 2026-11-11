use super::*;
use futures::{stream, StreamExt};

#[derive(Clone, Copy, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum RefreshReason {
    Manual,
    Opened,
    Timer,
    WindowChanged,
}
#[derive(Clone, Copy, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum PeopleFilter {
    All,
    Following,
    Organizations,
}
#[derive(Serialize)]
pub struct PersonVisibility {
    pub person: Person,
    pub hidden: bool,
    pub is_you: bool,
}

struct Roster {
    people: Vec<Person>,
    complete: bool,
}

impl BoardCore {
    pub fn people(&self, search: &str, filter: PeopleFilter) -> Vec<PersonVisibility> {
        let state = self.state.lock().unwrap();
        let search = search.to_lowercase();
        let mut people: Vec<_> = state
            .saved
            .people
            .iter()
            .filter(|p| {
                let source = match filter {
                    PeopleFilter::All => true,
                    PeopleFilter::Following => p.following,
                    PeopleFilter::Organizations => !p.organizations.is_empty(),
                };
                source
                    && (p.login.to_lowercase().contains(&search)
                        || p.name
                            .as_deref()
                            .unwrap_or("")
                            .to_lowercase()
                            .contains(&search))
            })
            .map(|p| PersonVisibility {
                person: p.clone(),
                hidden: state.saved.hidden(&p.login),
                is_you: state.saved.owner.as_ref() == Some(&p.login),
            })
            .collect();
        people.sort_by_key(|p| p.person.login.to_lowercase());
        people
    }
    async fn api(&self, path: &str, token: &str) -> Result<String, String> {
        self.http
            .request(Request {
                url: format!("https://api.github.com/{path}"),
                token: Some(token.into()),
                form: None,
            })
            .await
    }
    async fn pages(&self, path: &str, token: &str) -> Result<Vec<Person>, String> {
        let mut people = vec![];
        for page in 1u32.. {
            let text = self
                .api(&format!("{path}?per_page=100&page={page}"), token)
                .await?;
            let batch: Vec<GitHubPerson> =
                serde_json::from_str(&text).map_err(|_| "Could not read GitHub's people list")?;
            let done = batch.len() < 100;
            for person in batch {
                people.push(Person::try_from(person)?);
            }
            if done {
                return Ok(people);
            }
        }
        Err("Too many pages in GitHub's people list".into())
    }
    async fn roster(&self, token: &str) -> Result<Roster, String> {
        let owner: GitHubPerson = serde_json::from_str(&self.api("user", token).await?)
            .map_err(|_| "Could not read your GitHub profile")?;
        let owner = Person::try_from(owner)?;
        let mut complete = true;
        let following = self
            .pages("user/following", token)
            .await
            .unwrap_or_else(|_| {
                complete = false;
                vec![]
            });
        let orgs = self.pages("user/orgs", token).await.unwrap_or_else(|_| {
            complete = false;
            vec![]
        });
        let mut people = vec![owner];
        for mut person in following {
            person.following = true;
            merge_person(&mut people, person);
        }
        for org in orgs {
            for mut person in self
                .pages(&format!("orgs/{}/members", org.login), token)
                .await
                .unwrap_or_else(|_| {
                    complete = false;
                    vec![]
                })
            {
                person.organizations.push(org.login.clone());
                merge_person(&mut people, person);
            }
        }
        Ok(Roster { people, complete })
    }
    pub async fn refresh(&self, reason: RefreshReason) -> Result<(), String> {
        let Some(token) = self.credentials.get()? else {
            return Ok(());
        };
        let (generation, sync_people) = {
            let mut state = self.state.lock().unwrap();
            if state.refreshing {
                return Ok(());
            }
            if matches!(reason, RefreshReason::Opened | RefreshReason::WindowChanged)
                && !state.saved.people.is_empty()
                && state
                    .saved
                    .people
                    .iter()
                    .filter(|p| !state.saved.hidden(&p.login))
                    .all(|p| {
                        state.saved.counts.get(&p.login).is_some_and(|s| {
                            self.clock.now() - s.updated <= 120
                                && s.as_of == Some(self.clock.today())
                        })
                    })
            {
                return Ok(());
            }
            state.refreshing = true;
            state.error = None;
            let sync = reason == RefreshReason::Manual
                || state
                    .people_attempt
                    .is_none_or(|t| self.clock.now() - t >= 900);
            if sync {
                state.people_attempt = Some(self.clock.now());
            }
            (state.generation, sync)
        };
        if sync_people {
            let result = self.roster(&token).await;
            let mut state = self.state.lock().unwrap();
            if state.generation != generation {
                return Ok(());
            }
            match result {
                Ok(Roster {
                    mut people,
                    complete,
                }) => {
                    let owner = people[0].login.clone();
                    if state.saved.owner.as_ref() != Some(&owner) {
                        state.saved.owner = Some(owner);
                        state.saved.counts.clear();
                        state.saved.people_updated = None;
                    } else if !complete {
                        // Successful sources can add competitors, but only a complete
                        // roster can remove saved people or source memberships.
                        let fetched = people;
                        people = state.saved.people.clone();
                        for person in fetched {
                            merge_person(&mut people, person);
                        }
                    }
                    let before: Vec<_> = state.saved.people.iter().map(|p| &p.login).collect();
                    let after: Vec<_> = people.iter().map(|p| &p.login).collect();
                    if before != after {
                        state.baseline = None;
                        state.previous.clear();
                    }
                    state.saved.people = people;
                    if complete {
                        state.saved.people_updated = Some(self.clock.now());
                        state.people_error = None;
                    } else {
                        state.people_error = Some(
                            "Some people couldn't sync. Saved people are kept. Refresh to retry."
                                .into(),
                        );
                    }
                }
                _ => {
                    state.people_error = Some(
                        "People couldn't sync. Your previous list is saved. Refresh to retry."
                            .into(),
                    )
                }
            }
        }
        let logins: Vec<_> = {
            let state = self.state.lock().unwrap();
            if state.generation != generation {
                return Ok(());
            }
            state
                .saved
                .people
                .iter()
                .filter(|p| !state.saved.hidden(&p.login))
                .map(|p| p.login.clone())
                .collect()
        };
        let results: Vec<_> = stream::iter(logins.into_iter().map(|login| async move {
            let result = self
                .http
                .request(Request {
                    url: format!("https://github.com/users/{login}/contributions"),
                    token: None,
                    form: None,
                })
                .await
                .and_then(|html| parser::parse(&html));
            (login, result)
        }))
        .buffer_unordered(6)
        .collect()
        .await;
        let mut state = self.state.lock().unwrap();
        if state.generation != generation {
            return Ok(());
        }
        state.failed.clear();
        for (login, result) in results {
            match result {
                Ok(days) => {
                    state.saved.counts.insert(
                        login,
                        Snapshot {
                            days,
                            updated: self.clock.now(),
                            as_of: Some(self.clock.today()),
                        },
                    );
                }
                Err(_) => {
                    state
                        .failed
                        .insert(login, "Could not refresh Contributions".into());
                }
            }
        }
        state.refreshing = false;
        if !state.failed.is_empty() {
            state.error = Some("Some Contributions couldn't refresh. Saved numbers are still shown. Refresh to retry.".into());
        }
        let notifications =
            movement::finish_refresh(&mut state, self.clock.today(), self.clock.now());
        let result = self.persist(&state);
        drop(state);
        for notification in notifications {
            self.notifier.post(notification);
        }
        result
    }
}
fn merge_person(people: &mut Vec<Person>, person: Person) {
    if let Some(existing) = people.iter_mut().find(|p| p.login == person.login) {
        existing.following |= person.following;
        for org in person.organizations {
            if !existing.organizations.contains(&org) {
                existing.organizations.push(org);
            }
        }
    } else {
        people.push(person);
    }
}
