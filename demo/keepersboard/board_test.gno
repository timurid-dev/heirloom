package keepersboard

import (
	"chain"
	"strconv"
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"

	"gno.land/r/g1klfptn25xf37smf27vqr4g6qlmtwc0lz6y5mcj/heirloom/v1"
)

var (
	anna     = testutils.TestAddress("anna")
	stranger = testutils.TestAddress("stranger")
)

const blocksPerDay = 24 * 60 * 60 / 5

func resetBoard() {
	notes = avl.Tree{}
	pinned = 0
	lastID = 0
}

func TestBoardPassesToTheSuccessor(cur realm, t *testing.T) {
	resetBoard()
	testing.SetRealm(testing.NewUserRealm(stranger))
	first := Post(cross(cur), "  hello   from\nthe tavern  ")
	uassert.Equal(t, "hello from the tavern", mustGetNote(first).Text)

	uassert.AbortsContains(t, cur, "only the keeper can do this", func() {
		Pin(cross(cur), first)
	})

	testing.SetRealm(testing.NewUserRealm(founder))
	Pin(cross(cur), first)
	uassert.Equal(t, first, pinned)
	will := heirloom.CreateWill(cross(cur), anna.String()+":100", "1", anna)
	uassert.True(t, strings.Contains(Render(""), "anyone but the founder can ask to release the founder's [will "+strconv.Itoa(will)+"]("))

	testing.SkipHeights(blocksPerDay + 12)
	uassert.True(t, strings.Contains(Render(""), "is due"))
	testing.SetRealm(testing.NewUserRealm(stranger))
	heirloom.Release(cross(cur), will)
	uassert.True(t, strings.Contains(Render(""), "Someone asked to release the founder's"))
	uassert.Equal(t, founder, Keeper())

	testing.SkipHeights(7*blocksPerDay + 12)
	heirloom.Release(cross(cur), will)
	uassert.Equal(t, anna, Keeper())

	testing.SetRealm(testing.NewUserRealm(founder))
	uassert.AbortsContains(t, cur, "only the keeper can do this", func() {
		Remove(cross(cur), first)
	})

	testing.SetRealm(testing.NewUserRealm(anna))
	Remove(cross(cur), first)
	uassert.Equal(t, 0, pinned)
	page := Render("")
	uassert.True(t, strings.Contains(page, "now run by"))
	uassert.True(t, strings.Contains(page, "No notes yet."))
}

func TestNotesAreCheckedAndEscaped(cur realm, t *testing.T) {
	resetBoard()
	testing.SetRealm(testing.NewUserRealm(stranger))
	uassert.AbortsContains(t, cur, "a note must be 1 to 280 characters", func() {
		Post(cross(cur), "   ")
	})
	uassert.AbortsContains(t, cur, "a note must be 1 to 280 characters", func() {
		Post(cross(cur), strings.Repeat("x", maxNoteLen+1))
	})
	Post(cross(cur), "# heading [link](javascript:alert(1)) <b>")
	page := Render("")
	uassert.False(t, strings.Contains(page, "](javascript:"))
	uassert.False(t, strings.Contains(page, "<b>"))
	uassert.False(t, strings.Contains(page, "\n# heading"))
}

func TestNotesAreCountedInCharacters(cur realm, t *testing.T) {
	resetBoard()
	testing.SetRealm(testing.NewUserRealm(stranger))
	id := Post(cross(cur), strings.Repeat("ж", maxNoteLen))
	uassert.Equal(t, maxNoteLen, len([]rune(mustGetNote(id).Text)))
	uassert.AbortsContains(t, cur, "a note must be 1 to 280 characters", func() {
		Post(cross(cur), strings.Repeat("ж", maxNoteLen+1))
	})
}

func TestUnknownPagesAreNotFound(t *testing.T) {
	uassert.True(t, strings.Contains(Render("anything"), "# Page not found"))
	uassert.True(t, strings.Contains(Render("/"), "# The Keeper's Board"))
}

func TestTheBoardRefusesCoins(cur realm, t *testing.T) {
	resetBoard()
	testing.SetRealm(testing.NewUserRealm(stranger))
	testing.SetOriginSend(chain.Coins{{"ugnot", 1}})
	uassert.AbortsWithMessage(t, cur, "the board does not accept coins", func() {
		Post(cross(cur), "hi")
	})
	testing.SetOriginSend(nil)
	uassert.Equal(t, 1, Post(cross(cur), "hi"))
	uassert.True(t, strings.Contains(Render(""), "[the founder's wills]("+heirloom.UserURL(founder)+")"))
	uassert.True(t, strings.Contains(Render(""), "[Heirloom]("+heirloom.HomeURL()+")"))
}
