# tw-context-multiplex.sh
provides command cmx to apply and mange multiple contexts simultaneously

The taskwarrior context command allows users to declare a persistent filter for times when the user is in a certain context (home, work, shopping, etc.) This script (cmx.sh) is a method for users to engage more than one context at a time. For example, time-of-day or day-of-the-week could be contexts that one might want to use simultaneously, but taskwarrior context command can only invoke one defined context at a time. The cmx command is used much like the context command, but can handle and combine any of the pre-defined contexts, found in .taskrc. It does this by writing a cmx config in .taskrc, and using that to write a compound context variable.

So if these contexts were defined;
```
context.work.read=+work or +office or proj:foo
context.home.read=+home or +yard or +garage or proj:reno
context.morning.read=-afternoon -eve -nite
context.nite.read=-morning -afternoon -day -eve
```
if the following command is issued;
```
task context work
```
then the following variable is written to .taskrc, and the associated filter is applied;
```
context=work
```
The cmx command uses 2 taskrc varables; "context.cmx.read=" and "cmx.contexts=", so with the command;
```
task cmx work,morning
```
then the value of cmx.contexts becomes;
```
cmx.contexts=work,morning
```
the value of context.cmx.read becomes;
```
context.cmx.read=( +work or +office or proj:foo ) and ( -afternoon -eve -nite )
```
and the native context variable is set to;
```
context=cmx
```
This new cmx command doesn't change the function of the existing `task context` command, which would still be used to define, delete, set or clear context variables, like usual, but cmx is used to add or remove more than one context. This could even be done by external scripts, like cron jobs, for example. 

cmx sub-commands;
`cmx` with no sub-command reads the current `cmx.contexts=` variable(s) (if any) collects those values from the defined context(s) (if any) writes `context.cmx.read=` and/or `context.cmx.write=` variables, and then sets the `context=cmx` variable. 

`cmx context1,context2,contextN` clears any existing `cmx.contexts=` value, then combines those new context values.

`cmx +context3` adds context3 to the existing set (not to be confused with taskwarrior tag-related commands)

`cmx -context2` removes context2 from the current set

`cmx none` clears all cmx values and un-sets `context=` 

