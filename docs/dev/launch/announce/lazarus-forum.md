**Subject:** kbool 0.1.0: FPC classes ported to bash (TStringList, TDictionary, TIniFile …), feedback on API fidelity welcome

Hello all,

I have been working on kbool, a toolkit that brings Free Pascal habits to bash scripts, and I
would like to hear from people who know the FPC classes far better than a shell does. Version
0.1.0 is the first release: <https://github.com/Keksov/kbool> (MIT).

What it is:

* **Units with `uses`**: `kk.uses tstringlist tdictionary` loads each unit once, by name, from a
  search path.
* **Classes written as `class … end`**: the declaration first, like an interface section, then the
  method bodies as ordinary bash functions, then `build`:

```bash
source kbool/kbool.sh || exit
kk.uses kklass_pascal || exit

class TCounter
    public
        var         Name
        var         Count
        constructor Create
        proc        Add
        func        Report
end

TCounter.Create() { Name="$1"; Count=0; }
TCounter.Add()    { Count=$(( Count + ${1:-1} )); }
TCounter.Report() { RESULT="$Name: $Count"; }
build TCounter
```

  Inheritance is `class TDog : TAnimal`, `inherited` works in methods, constructors and
  destructors, every method is virtual, and `override` is a build-time check that an ancestor has
  the method.
* **A class library (kcl)** of ports: `TList`, `TStringList`, `TObjectList`, `TDictionary` /
  `TObjectDictionary`, `THashSet`, `TQueue` / `TStack`, `TIniFile` / `TMemIniFile`,
  `TCustomApplication` (the option parser is a line-by-line port of FPC 3.2.2 `custapp.pp`),
  `DateUtils` (185 members), `Math` (123 members), `TStringHelper`, `TArray`, plus the Delphi
  `System.IOUtils` trio `TPath` / `TFile` / `TDirectory` and `TRegEx`.

```bash
kk.uses tstringlist tinifile || exit
TStringList.new names
names.Add Wirth; names.Add Hejlsberg; names.Sort
names.Get 0; echo "$RESULT"                      # => Hejlsberg

TMemIniFile.new cfg settings.ini
cfg.WriteString main editor lazarus
cfg.UpdateFile
cfg.ReadString main editor vim; echo "$RESULT"   # => lazarus
```

Bash forces some differences, and I would rather have them named than hidden. A member returns its
value in `RESULT` instead of stdout (a subshell is a fork, and forks are slow); errors are rc 1 or
rc 2 rather than exceptions. Each unit's README lists its deviations from FPC, some with the FPC
source line where it was checked against FPC (`math.pp:1224` for `sumInt`, `dateutil.inc:2849`
for ISO date parsing). A few others: `TDictionary.SetItem` is update-only as in FPC, the sorted set
classes are not ported, `TRegEx` runs on POSIX ERE, not PCRE.

**The feedback I am after:** where does a port behave differently from what you expect of the FPC
class? Which deviations look wrong to you? Which classes would you want next (`fpjson` is planned
but not written)? The unit table with every deviation is here:
<https://github.com/Keksov/kcl>.

Tests run on bash 5.1 to 5.3 on Linux, macOS, FreeBSD and Windows (13 CI configurations). It was
developed with AI assistance: I made the design decisions and every change reaches the main branch
through me; the process is described in the README under "How it was built".

kbool is also a small tribute to Niklaus Wirth. Thank you for reading.
