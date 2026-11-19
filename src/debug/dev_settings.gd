class_name DevSettings
extends RefCounted
## Developer-mode switches, local to this machine.

## Single-player mode: the seated pilot also runs the ballast (Numpad 8 blow,
## Numpad 2 flood). Toggle with F5, or start with `--solo`.
static var single_player: bool = OS.get_cmdline_user_args().has("--solo")
