**Subject:** Delphi-style classes in bash: TPath, TFile, TRegEx, TDictionary ported, looking for API feedback

Hello,

this is a slightly unusual project for this forum, but its audience is Delphi people. kbool brings
Pascal habits to bash scripts: units you load by name, classes declared as `class … end`, and a
class library with names you already know. Version 0.1.0 is the first release:
<https://github.com/Keksov/kbool> (MIT).

A class in kbool's Pascal DSL, with inheritance:

```bash
source kbool/kbool.sh || exit
kk.uses kklass_pascal || exit

class TAnimal
    public
        var         Name
        constructor Create
        proc        Speak
end
TAnimal.Create() { Name="$1"; }
TAnimal.Speak()  { echo "$Name makes a sound"; }
build TAnimal

class TDog : TAnimal
    public
        var           Breed
        constructor   Create
        override proc Speak
end
TDog.Create() { inherited; Breed="${2:-mutt}"; }
TDog.Speak()  { echo "$Name barks"; inherited Speak; }
build TDog

TDog.new rex Rex beagle
rex.Speak          # Rex barks / Rex makes a sound
rex.delete
```

Dispatch follows the `virtual; override;` model: `$this.Method` is a virtual call, `inherited` is
static and resolves from the class whose body is running. Properties can have `read` / `write`
members, there are `public` / `private` / `protected` sections, static members, constructors and
destructors.

The ports with a Delphi origin: `TPath`, `TFile` and `TDirectory` (`System.IOUtils`), `TRegEx`
(`System.RegularExpressions`), `TStopwatch` (`System.Diagnostics`). Next to them are FPC ports:
`TStringList`, `TDictionary` / `TObjectDictionary`, `THashSet`, `TQueue` / `TStack`, `TIniFile` /
`TMemIniFile`, `TCustomApplication`, `DateUtils`, `Math`, `TStringHelper`.

The library started as a port of the Free Pascal RTL/FCL, so the FPC-derived classes keep FPC's
semantics, and that is where I would most like Delphi eyes. One example: `TDictionary.SetItem` on
a missing key fails and inserts nothing, as in FPC; Delphi would insert. Bash adds its own differences: a member returns its value in `RESULT` rather than on
stdout, because a `$( )` subshell is a fork and costs about 16 ms on Windows; errors are exit codes
(rc 1 / rc 2), not exceptions; `TRegEx` is POSIX ERE, so there are no lazy quantifiers or
lookaround; `TStopwatch` has no `TTimeSpan`. Every deviation is listed in the unit table:
<https://github.com/Keksov/kcl>.

**Questions for you:** do the names and semantics match what you would expect from the RTL classes?
Which deviations would surprise you in practice? Where FPC and Delphi differ, which behaviour would
you expect a bash port to follow?

It runs on bash 5.1 or newer: Linux, macOS (with Homebrew bash), FreeBSD, and Windows under Git-bash
or MSYS2, with 13 CI configurations on every push. The project was developed with AI assistance,
with the design decisions and every merge made by me; the README section "How it was built"
describes the process.

Thanks for any feedback.
