# Announcement drafts (launch L8.5)

Drafts for the 0.1.0 announcement. **Nothing here has been posted.** The owner decides where and
when (OG6) and posts. The texts were written by an AI worker from facts in the repository; the Habr
article and the forum posts are in the owner's first person, so read them as your own words and
change what does not sound like you.

## The drafts

| file | venue | language | length | what it is |
|---|---|---|---|---|
| [lazarus-forum.md](lazarus-forum.md) | Lazarus / Free Pascal forum, <https://forum.lazarus.freepascal.org/> (board: owner's choice) | English | ~440 words with code | soft launch: the FPC ports, `class … end`, a request for feedback on API fidelity |
| [delphi-praxis.md](delphi-praxis.md) | Delphi-PRAXiS, <https://en.delphipraxis.net/> (board: owner's choice) | English | ~410 words with code | soft launch: the Delphi-origin ports, dispatch model, where FPC and Delphi differ |
| [show-hn.md](show-hn.md) | Hacker News, Show HN | English | title + ~250 words | title, URL, first comment; the AI-assistance fact comes first |
| [reddit-bash.md](reddit-bash.md) | r/bash | English | title + ~320 words with code | the language features and the portability layer |
| [reddit-commandline.md](reddit-commandline.md) | r/commandline | English | title + ~320 words with code | the notes demo and the tool wrappers |
| [lobsters.md](lobsters.md) | lobste.rs | English | title + tags + ~180-word comment | title, tags, author comment; a note on the `vibecoding` tag |
| [habr-ru.md](habr-ru.md) | Habr | Russian | ~1900 words + code | the full article: problem, classes, library, demo, portability, costs, how it was built, how to try it |
| [faq.md](faq.md) | any thread | English | 8 answers | prepared answers: Python, speed, Pascal, AI-written code, bash 3.2, GNU tools, license, contributing |

Every draft says plainly that kbool was developed with AI assistance (DL4). Only the Show HN comment
leads with it; the Habr article gives it a section of its own.

## Sequencing

From [LAUNCH_PLAN.md](../../LAUNCH_PLAN.md), row L8.5:

1. **Soft launch** on the Pascal forums: the Lazarus / Free Pascal forum and Delphi-PRAXiS. About
   one week of feedback; fix what the Pascal people find before the wider launch.
2. **Then** Show HN, r/bash, r/commandline, lobste.rs and Habr.

## Before posting: the owner's checklist

- [ ] The release exists: the 0.1.0 tag is in all five repos (kbool, kcl, kklass, kkore, ktests)
      and the GitHub Releases are published (L8.4).
- [ ] The README status line says the 0.x wording from OG5, not "pre-release".
- [ ] The CI badge on <https://github.com/Keksov/kbool> is green for the tagged commit.
- [ ] Every link in the draft you post opens. They were checked on 2026-10-31; re-check:
      `https://github.com/Keksov/kbool`, `/blob/main/docs/portability.md`,
      `/blob/main/docs/benchmarks.md`, `/blob/main/docs/dev/README.md`,
      `/blob/main/CONTRIBUTING.md`, `/blob/main/SECURITY.md`, and `https://github.com/Keksov/kcl`.
- [ ] `bash examples/notes_session.sh` still prints the session shown in habr-ru.md and
      reddit-commandline.md (the port number differs per run; that transcript is from the L8.1
      fresh install on kb-ubuntu).
- [ ] Figures that change with every commit are current. show-hn.md quotes 627 of 795 commits with
      a `Co-Authored-By: Claude` trailer (all five repos, 2026-10-31); recount with
      `for r in . kcl kklass kkore ktests; do git -C $r rev-list --count HEAD; git -C $r log --format=%B | grep -c '^Co-Authored-By: Claude'; done`.
      The line count of `examples/notes.sh` ("about 175 lines" of code without comments and
      blank lines, habr-ru.md and reddit-commandline.md) should match examples/README.md.
- [ ] The venue's current rules on self-promotion and on AI-written or AI-assisted posts are read,
      and the draft is adjusted to them.
- [ ] Lobsters: decide on the `vibecoding` tag (see lobsters.md).
- [ ] Habr: hubs and tags chosen.
