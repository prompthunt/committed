#!/usr/bin/env python3
"""Apply the App Store listing in appstore/metadata to App Store Connect.

Re-runnable: every step reads App Store Connect first and writes only what differs, so a
second run in a row makes no changes. See appstore/README.md.

  python3 scripts/appstore_apply.py            # apply
  python3 scripts/appstore_apply.py --dry-run  # show what would change, write nothing

Needs the `asc` CLI signed in with the Prompt Hunt API key (`asc auth status`). It never
starts an Apple ID web sign-in: a step that only `asc web` can do is printed for you to run.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

APP_ID = '6831797452'
VERSION = '1.0.2'
PLATFORM = 'IOS'
LOCALE = 'en-US'
COPYRIGHT = '2026 Prompt Hunt, Inc.'
CONTENT_RIGHTS = 'USES_THIRD_PARTY_CONTENT'  # GitHub usernames and avatars, under GitHub's API terms
RELEASE_TYPE = 'MANUAL'
INCLUDE = 'localizations,categories,age-rating,review-information'
METADATA = Path(__file__).resolve().parent.parent / 'appstore' / 'metadata'

# Apple's limits, in characters unless noted.
LIMITS = {
    ('app-info', 'name'): 30,
    ('app-info', 'subtitle'): 30,
    ('version', 'promotionalText'): 170,
    ('version', 'description'): 4000,
    ('version', 'whatsNew'): 4000,
    ('review', 'notes'): 4000,
}
KEYWORD_BYTES = 100
# Glossary: say "Connect GitHub" and "Sample board", never these.
BANNED = ('demo account', 'guest', 'sign in', 'sign-in', 'signin', 'sign up', 'log in', 'login', 'log out')
EMAIL = re.compile(r'[\w.+-]+@[\w-]+\.[\w.]+')
CONTACT_FIELDS = ('contactFirstName', 'contactLastName', 'contactPhone', 'contactEmail')


def load_listing(directory):
    """Every JSON file in the metadata tree, keyed by its path relative to the tree."""
    directory = Path(directory)
    return {path.relative_to(directory).as_posix(): json.loads(path.read_text())
            for path in sorted(directory.rglob('*.json'))}


def listing_problems(files):
    """Reasons the listing would be rejected or would break the glossary; empty when it's fine."""
    problems = []
    app_info = files.get(f'app-info/{LOCALE}.json', {})
    version = files.get(f'version/{VERSION}/{LOCALE}.json', {})
    review = files.get('review-information.json', {})
    sources = {'app-info': app_info, 'version': version, 'review': review}
    for (source, field), limit in LIMITS.items():
        value = sources[source].get(field) or ''
        if len(value) > limit:
            problems.append(f'{field} is {len(value)} characters; the limit is {limit}.')
    keywords = version.get('keywords') or ''
    if len(keywords.encode()) > KEYWORD_BYTES:
        problems.append(f'keywords are {len(keywords.encode())} bytes; the limit is {KEYWORD_BYTES}.')
    terms = keywords.split(',')
    if any(term != term.strip() or not term for term in terms):
        problems.append('keywords must be a comma list with no empty terms or spaces around commas.')
    if len(set(term.lower() for term in terms)) != len(terms):
        problems.append('keywords repeat a term.')
    text = {'subtitle': app_info.get('subtitle'), 'description': version.get('description'),
            'keywords': keywords, 'promotionalText': version.get('promotionalText'),
            'whatsNew': version.get('whatsNew'), 'notes': review.get('notes')}
    for field, value in text.items():
        lowered = (value or '').lower()
        for phrase in BANNED:
            if re.search(rf'\b{re.escape(phrase)}\b', lowered):
                problems.append(f'{field} says "{phrase}"; the glossary rules it out.')
        if EMAIL.search(value or ''):
            problems.append(f'{field} contains an email address; listing text has no public email.')
    for field in CONTACT_FIELDS:
        if field in review:
            problems.append(f'review-information.json has {field}; contact details come from App Store Connect, not the public repo.')
    return problems


def review_contact(beta_details):
    """The contact on the app's TestFlight beta review details, reused for App Review."""
    data = beta_details.get('data') or []
    attributes = (data[0] if data else {}).get('attributes') or {}
    contact = {field: attributes.get(field) for field in CONTACT_FIELDS}
    missing = [field for field, value in contact.items() if not value]
    if missing:
        sys.exit(f'TestFlight beta review details lack {", ".join(missing)}; fill them in App Store Connect first.')
    return contact


def asc(*args, ok=(0,)):
    # Run outside the repo: asc writes failure reports under ./.asc/.
    result = subprocess.run(['asc', *args], capture_output=True, text=True, cwd=tempfile.gettempdir())
    if result.returncode not in ok:
        sys.exit(f'asc {" ".join(args)} failed ({result.returncode}):\n{result.stdout}\n{result.stderr}'.rstrip())
    return result


def asc_json(*args):
    return json.loads(asc(*args, '--output', 'json').stdout)


class Run:
    def __init__(self, dry_run):
        self.dry_run = dry_run
        self.changes = []
        self.pending = []

    def change(self, description, *args):
        """Record a change and make it, unless this is a dry run."""
        self.changes.append(description)
        print(f'  {"would change" if self.dry_run else "changing"}: {description}')
        if not self.dry_run:
            asc(*args)


def version_id():
    for version in asc_json('versions', 'list', '--app', APP_ID, '--paginate')['data']:
        attributes = version['attributes']
        if attributes['versionString'] == VERSION and attributes['platform'] == PLATFORM:
            return version['id']
    sys.exit(f'App {APP_ID} has no {PLATFORM} version {VERSION}.')


def apply_metadata(run, workdir, version):
    print('Listing text, categories, age rating, review details (asc metadata)')
    stage = workdir / 'metadata'
    shutil.copytree(METADATA, stage)
    review_path = stage / 'review-information.json'
    review = json.loads(review_path.read_text())
    review.update(review_contact(asc_json('testflight', 'review', 'view', '--app', APP_ID)))
    review_path.write_text(json.dumps(review, indent=2))

    # asc 6.5 `metadata apply` can only update review details, not create them ("detailID is
    # required"), so the first run creates them here.
    detail = asc_json('review', 'details-for-version', '--version-id', version).get('data') or {}
    creating_detail = not detail.get('id')
    if creating_detail:
        run.change('create App Review details (contact from TestFlight, notes, no demo account)',
                   'review', 'details-create', '--version-id', version,
                   '--contact-first-name', review['contactFirstName'], '--contact-last-name', review['contactLastName'],
                   '--contact-phone', review['contactPhone'], '--contact-email', review['contactEmail'],
                   '--demo-account-required=false', '--notes', review['notes'])

    common = ['--app', APP_ID, '--version', VERSION, '--platform', PLATFORM, '--dir', str(stage), '--include', INCLUDE]
    plan = asc_json('metadata', 'plan', *common, '--review-dir', str(workdir / 'review'))['plan']
    if plan['deletes']:
        sys.exit(f'asc metadata plan wants to delete {[entry["key"] for entry in plan["deletes"]]}; refusing.')
    entries = plan['adds'] + plan['updates']
    if creating_detail and run.dry_run:  # the create above already covers these
        entries = [entry for entry in entries if entry['scope'] != 'review-information']
    if not entries:
        print('  unchanged')
        return
    for entry in entries:
        run.changes.append(entry['key'])
        print(f'  {"would set" if run.dry_run else "setting"}: {entry["key"]}')
    if not run.dry_run:
        asc('metadata', 'apply', *common)


def apply_version(run, version):
    print(f'Version {VERSION}: copyright and release type')
    attributes = asc_json('versions', 'view', '--version-id', version)['data']['attributes']
    flags, described = [], []
    if attributes.get('copyright') != COPYRIGHT:
        flags += ['--copyright', COPYRIGHT]
        described.append(f'copyright {attributes.get("copyright")!r} -> {COPYRIGHT!r}')
    if attributes.get('releaseType') != RELEASE_TYPE:
        flags += ['--release-type', RELEASE_TYPE]
        described.append(f'release type {attributes.get("releaseType")} -> {RELEASE_TYPE}')
    if flags:
        run.change(', '.join(described), 'versions', 'update', '--version-id', version, *flags)
    else:
        print('  unchanged')
    phased = asc('versions', 'phased-release', 'view', '--version-id', version, '--output', 'json', ok=(0, 1))
    if phased.returncode == 0 and (json.loads(phased.stdout or '{}').get('data') or {}).get('id'):
        print('  warning: this version has a phased release; the listing wants none. Remove it in App Store Connect.')


def apply_content_rights(run):
    print('Content rights')
    current = asc_json('apps', 'view', '--id', APP_ID)['data']['attributes'].get('contentRightsDeclaration')
    if current == CONTENT_RIGHTS:
        print('  unchanged')
    else:
        run.change(f'content rights {current} -> {CONTENT_RIGHTS}',
                   'apps', 'update', '--id', APP_ID, '--content-rights', CONTENT_RIGHTS)


def apply_price(run):
    print('Price: Free')
    # Exits 1, still printing {"configured": false}, while the app has no price schedule.
    result = asc('pricing', 'current', '--app', APP_ID, '--output', 'json', ok=(0, 1))
    try:
        current = json.loads(result.stdout)
    except json.JSONDecodeError:
        sys.exit(f'asc pricing current failed:\n{result.stderr or result.stdout}')
    if current.get('configured') is False:
        # Creating a schedule replaces the whole schedule, so only ever do it when there's none.
        run.change('price schedule -> Free (base territory USA)',
                   'pricing', 'schedule', 'create', '--app', APP_ID, '--free', '--base-territory', 'USA')
    elif current.get('isFree') is True:
        print('  unchanged')
    else:
        print(f'  warning: the price isn\'t Free; set it in App Store Connect. Current: {json.dumps(current)}')
        run.pending.append('price is not Free')


def apply_availability(run):
    print('Availability: every territory')
    view = asc('pricing', 'availability', 'view', '--app', APP_ID, '--output', 'json', ok=(0, 1))
    if view.returncode != 0:
        if 'no availability' not in (view.stdout + view.stderr):
            sys.exit(f'asc pricing availability view failed:\n{view.stderr or view.stdout}')
        description = 'availability -> every territory, and new territories'
        args = ['pricing', 'availability', 'create', '--app', APP_ID, '--all-territories', '--available', 'true',
                '--available-in-new-territories', 'true', '--if-exists', 'skip']
        run.changes.append(description)
        print(f'  {"would change" if run.dry_run else "changing"}: {description}')
        if run.dry_run:
            return
        created = asc(*args, ok=range(256))
        if created.returncode != 0:
            run.changes.pop()
            run.pending.append('availability')
            print('  Apple refused to set up availability through the API:')
            print('    ' + (created.stderr or created.stdout).strip().replace('\n', '\n    '))
            print('  Set it up once with an Apple ID web session (asc web, needs your sign-in and 2FA):')
            print(f'    asc web apps availability create --app {APP_ID} --territory <every territory> '
                  '--available-in-new-territories true')
            print('  or in App Store Connect > Pricing and Availability. Then re-run this script.')
        return
    availability = json.loads(view.stdout)['data']
    territories = asc_json('pricing', 'availability', 'territory-availabilities', '--app', APP_ID, '--paginate')['data']
    unavailable = [t['id'] for t in territories if not t['attributes'].get('available')]
    if not availability['attributes'].get('availableInNewTerritories'):
        print('  warning: new territories aren\'t automatic, and Apple has no API to change that. '
              'Turn it on in App Store Connect > Pricing and Availability.')
        run.pending.append('availability in new territories')
    if unavailable:
        run.change(f'make {len(unavailable)} unavailable territories available',
                   'pricing', 'availability', 'edit', '--app', APP_ID, '--all-territories', '--available', 'true')
    else:
        print(f'  unchanged ({len(territories)} territories available)')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--dry-run', action='store_true', help='show what would change; write nothing')
    args = parser.parse_args(argv)

    problems = listing_problems(load_listing(METADATA))
    if problems:
        sys.exit('The listing in appstore/metadata has problems:\n- ' + '\n- '.join(problems))

    run = Run(args.dry_run)
    version = version_id()
    with tempfile.TemporaryDirectory(prefix='appstore-apply-') as workdir:
        apply_metadata(run, Path(workdir), version)
    apply_version(run, version)
    apply_content_rights(run)
    apply_price(run)
    apply_availability(run)

    verb = 'would change' if run.dry_run else 'changed'
    print(f'\n{len(run.changes)} {verb}.' if run.changes else '\nNo changes.')
    if run.pending:
        print(f'Needs you: {", ".join(run.pending)} (see above).')
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
