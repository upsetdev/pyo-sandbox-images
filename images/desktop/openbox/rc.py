#!/usr/bin/env python3
"""Sets up Openbox's own rc.xml for the desktop, at build time.

    rc.py /etc/xdg/openbox/rc.xml

It keeps Openbox's key and mouse bindings and changes only the look: the
Pyo theme (themerc here), no window icon in title bars, titles and menus
in Inter, no iconify animation, one desktop instead of four, and new
windows in the middle of the screen. Each
change has to apply, so a new Openbox with a different rc.xml fails the
build instead of looking wrong.
"""

import re
import sys

path = sys.argv[1]
rc = open(path, encoding="utf-8").read()


def change(pattern: str, new: str, count: int = 1) -> None:
    global rc
    rc, n = re.subn(pattern, new, rc)
    if n != count:
        sys.exit(f"rc.py: {pattern!r} matched {n} times, not {count}")


change(r"<name>Clearlooks</name>", "<name>Pyo</name>")
change(r"<titleLayout>NLIMC</titleLayout>", "<titleLayout>LIMC</titleLayout>")
change(r"<animateIconify>yes</animateIconify>", "<animateIconify>no</animateIconify>")


def font(place: str, size: int, weight: str) -> None:
    change(
        rf'(<font place="{place}">\s*)<name>sans</name>(\s*)<size>\d+</size>((?:\s*<!--.*?-->)?\s*)<weight>\w+</weight>',
        rf"\1<name>Inter Variable</name>\g<2><size>{size}</size>\g<3><weight>{weight}</weight>",
    )


font("ActiveWindow", 9, "bold")
font("InactiveWindow", 9, "bold")
font("MenuHeader", 9, "bold")
font("MenuItem", 10, "normal")
font("ActiveOnScreenDisplay", 10, "bold")
font("InactiveOnScreenDisplay", 10, "bold")
change(r"<number>4</number>", "<number>1</number>")
# New windows open in the middle of the screen, unless they ask for a
# place of their own. The browser opens maximized anyway.
change(
    r"</applications>",
    '<application type="normal">\n  <position force="no"><x>center</x><y>center</y></position>\n</application>\n</applications>',
)

open(path, "w", encoding="utf-8").write(rc)
