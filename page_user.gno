package heirloom

import (
	"strconv"
	"strings"

	"gno.land/p/nt/ufmt/v0"
)

func renderUser(addr address, page int) string {
	made, madeMore := willsMadeBy(addr, page)
	named, namedMore := willsNaming(addr, page)
	succeeding, succeedingMore := willsPassingRightsTo(addr, page)
	if page > 1 && len(made) == 0 && len(named) == 0 && len(succeeding) == 0 {
		return notFound("Page not found")
	}

	var b strings.Builder
	b.WriteString("# " + shortAddr(addr) + "\n\n" + backLink() + "\n\n`" + addr.String() + "`\n\n")
	if holder := holderOf(addr); holder != addr {
		b.WriteString("Admin rights of this address now belong to " + userLink(holder) + ".\n\n")
	}
	var madeLines, namedLines, succeedingLines []string
	for _, w := range made {
		madeLines = append(madeLines, ufmt.Sprintf("- %s: %s\n", willLink(w.ID), string(w.status())))
	}
	for _, w := range named {
		namedLines = append(namedLines, ufmt.Sprintf("- %s of %s: %d%%, %s · %s\n", willLink(w.ID), userLink(w.Owner), w.heir(addr).Percent, string(w.status()), hideLink(w)))
	}
	for _, w := range succeeding {
		succeedingLines = append(succeedingLines, ufmt.Sprintf("- %s of %s: %s · %s\n", willLink(w.ID), userLink(w.Owner), string(w.status()), hideLink(w)))
	}
	b.WriteString(section("Wills made", madeLines, page))
	b.WriteString(section("Named as heir", namedLines, page))
	b.WriteString(section("Named as successor", succeedingLines, page))
	if len(namedLines) > 0 || len(succeedingLines) > 0 {
		b.WriteString("If this is your address, hide takes a will off this page; you can still be paid, and Unhide puts it back.\n\n")
	}
	if madeMore || namedMore || succeedingMore {
		b.WriteString(userPageLink("More", addr, page+1) + "\n")
	}
	return b.String()
}

func section(title string, lines []string, page int) string {
	if len(lines) == 0 {
		if page == 1 {
			return "## " + title + "\n\nNone.\n\n"
		}
		return ""
	}
	var b strings.Builder
	b.WriteString("## " + title + "\n\n")
	for _, line := range lines {
		b.WriteString(line)
	}
	return b.String() + "\n"
}

func hideLink(w *Will) string {
	return link("hide", txURL("Hide", 0, "id", strconv.Itoa(w.ID)))
}
