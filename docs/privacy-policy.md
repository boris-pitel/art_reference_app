# Privacy Policy

**Version 1.0 — effective 21 August 2026**

Painter Reference is a reference-image library for artists. This policy explains
what the service stores, why, who else is involved, and what you can do about it.

It is written to be read. If anything here is unclear, ask —
[borispitel1@gmail.com](mailto:borispitel1@gmail.com).

> **[CONFIRM BEFORE PUBLISHING]** Three things I cannot fill in for you:
> the legal entity or individual name that operates the service, the country
> whose law governs it, and the region your Supabase project runs in (visible in
> the Supabase dashboard under Project Settings). The last one matters for the
> International transfers section below.

---

## Who operates this service

Painter Reference is operated by **[CONFIRM: name and country]**, contactable at
borispitel1@gmail.com. For data-protection purposes that party is the
*controller* — the one who decides what is collected and why.

## What is stored, and why

**Your account** — your email address, and a display name if you set one. Your
password is stored only as a cryptographic hash by our authentication provider;
it is never visible to us. If you sign in with Google we receive your email
address and name from Google, and no password exists.
*Why: to identify your library and let you sign back into it.*

**Your images** — the reference photographs and artwork you upload, together
with the smaller preview copies the app generates. Also the titles, notes,
author names, keywords and favourites you attach to them, and the categories you
organise them into.
*Why: this is the service. Without it there is no library.*

**Photo details taken from your images** — when a photograph carries camera
information, the app reads and stores the camera make and model, the lens, the
ISO setting, the capture date, and the image dimensions.
**The app does not read or store location data.** If your camera recorded where
a photograph was taken, that information is not extracted and is not stored in
our database.
*Why: so the Technical panel can show you how a reference was shot.*

**Messages** — if you use the messaging feature: your conversations, the
messages in them, any images you send, and who you have blocked. Also whether
you have chosen to be discoverable in user search.
*Why: to deliver messages and respect your blocking and visibility choices.*

**Feedback you send** — your comment, any screenshot you attach, which screen
you were on, and the app version.
*Why: to reproduce and fix what you reported.*

**Activity records** — what the app did and whether it worked: the operation
(for example uploading an image), whether it succeeded or failed, how long it
took, any error message, the platform, and the app version. Each record also
carries basic device information — device model, screen size, language, and
browser identification.
*Why: so a failure can be diagnosed. Several faults have only been fixable
because a record existed showing what happened on a device we could not
inspect.*

## What is never stored

- **Your password**, in any readable form.
- **Photograph location data.** Not extracted, not stored.
- **Payment details.** The service does not currently take payment.
- **Advertising or tracking identifiers.** There is no advertising, no
  third-party analytics, and no cross-site tracking of any kind.

## Why we are allowed to store it

For your account, library and messages, the legal basis is **performance of a
contract** — you asked for a reference library, and it cannot exist without
storing your images.

For activity records and feedback, the basis is **legitimate interest** in
keeping the service working and fixing what breaks. This is limited to what
diagnosis requires, and those records are never used to build a profile of you
or sold to anyone.

## Who else handles your data

Painter Reference is a small service built on other companies' infrastructure.
These are our processors — each handles data on our instructions and is not
permitted to use it for their own purposes.

| Provider | What they handle | Why |
|---|---|---|
| **Supabase** | Database, file storage, authentication | Stores your account, images and all other records |
| **Google Firebase Hosting** | Delivery of the web app | Serves painterreference.com to your browser |
| **Google** | Optional Sign in with Google | Only if you choose that sign-in method |
| **OpenAI** | Optional AI image analysis | Only when you ask for it — see below |

**About the AI feature.** When — and only when — you tap to analyse an image,
that image is sent to OpenAI for analysis and the result is returned to you.
Nothing is sent automatically, and no image leaves the service for AI analysis
unless you request it for that image. The provider and model in use are named in
the app's Help screen, and will be updated there if they change.

## Who can see your images

**You can.** Your library is scoped to your account, enforced at the database
level: another user's request for your images is refused by the database itself,
not merely hidden by the app.

**People you send images to can see what you sent them** — that is what sending
means. They cannot see the rest of your library.

**Administrators can.** The service operator can access accounts and their
contents for support and maintenance, and the app includes an impersonation
feature that lets an administrator view the app as a specific user in order to
reproduce a reported problem. This is disclosed here because you are entitled to
know it exists. It is used for support, and administrator actions are recorded
in the activity log.

## How long it is kept

**Your library and messages** are kept until you delete them, or until you
delete your account — at which point images, categories, messages and profile
are removed.

**Activity records and feedback** are kept while they remain useful for
diagnosis. **[CONFIRM: propose 12 months, then automatic deletion.]** There is
currently no automatic expiry; adding one is planned.

**Backups** held by our hosting providers may retain deleted content for a short
period before rotating out.

## Your rights

Wherever you live, you can ask us to:

- **show you** what we hold about you,
- **correct** anything wrong,
- **delete** your account and its contents,
- **give you a copy** of your images and data in a usable form,
- **stop** a particular use you object to.

Email borispitel1@gmail.com and we will act within 30 days. Account deletion
will also be available directly in the app.

If you are in the UK or EU and think we have handled your data badly, you may
complain to your national data-protection authority. We would rather you told us
first.

## International transfers

Our providers may process data outside your country **[CONFIRM: name the
Supabase region — for example "in the United States"]**. Where data leaves the
UK or EU, the transfer relies on the standard contractual clauses those
providers publish.

## Children

Painter Reference is not intended for children under 13, and accounts should not
be created for them.

## Security

Access is enforced at the database level rather than only in the app. Files are
served through short-lived signed links rather than public URLs. Passwords are
hashed by our authentication provider and are not visible to us. No system is
perfectly secure, but your library is not casually reachable by anyone else.

If we discover a breach affecting your data, we will tell you and the relevant
authority as the law requires.

## Changes to this policy

If this policy changes materially, we will tell you in the app and ask you to
read the new version. The version and date are at the top, and we keep a record
of which version each account accepted.

## Contact

**[CONFIRM: operator name]**
borispitel1@gmail.com
